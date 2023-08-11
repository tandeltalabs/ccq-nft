// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface FundCertWrap {
    function isNotExpired() external view returns(bool);
    function customTransferFrom(address from, address to, uint256 id, uint256 amount) external;
    function getPriceAtTime(uint256 time) external view returns(uint256);
    function getCurrentId() external view returns(uint256);
}

contract FundCertMarketplace is Ownable, ERC1155Receiver, ReentrancyGuard{
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;
    Counters.Counter private id;
    mapping(address => bool) public publishers;
    FundCertWrap fundCertWrap;
    address public paymentToken;
    bool public isOpen;
    uint256 decimals;
    bool unActivated = true;
    
    struct Item {
        uint256 id;
        uint256 nftId;
        address nftAddress;
        uint256 amount;
        address seller;
        FundCertWrap nftContract;
    }

    struct SellItem {
        uint256 id;
        uint256 amount;
    }

    struct Cart {
        uint256 id;
        uint256 amount;
    }

    Item[] public items;

    constructor(address _paymentToken, bool _isOpen, uint256 _decimals) {
        paymentToken = _paymentToken;
        isOpen = _isOpen;
        decimals = _decimals;
    }

    modifier onlyPublisher(address _publisher) {
        require(publishers[_publisher], "only publisher can sell nft in this market");
        _;
    }

    modifier whenMarketOpen() {
        require(isOpen, "market is closed");
        _;
    }

    event _eventListNewItemToMarket(uint256 id, uint256 nftId, uint256 amount, address seller);
    event _eventDelistItem(uint256 id, uint256 nftId, uint256 amount, address seller);
    event _eventBuyItemInMarket(uint256 id, uint256 nftId, uint256 amount, uint256 totalValue, address seller, address buyer, address contractAddress);

    function sellItem(
        address _nftAddress,
        SellItem[] memory sellItems
    ) whenMarketOpen onlyPublisher(msg.sender) public {
        if(unActivated){
            unActivated = false;
        }

        fundCertWrap = FundCertWrap(_nftAddress);
        require(fundCertWrap.isNotExpired(), "ETF was expired");

        for (uint i = 0; i < sellItems.length; i++) {
            SellItem memory _sellItem = sellItems[i];
            uint256 _nftId = _sellItem.id;
            uint256 _amount = _sellItem.amount;

            fundCertWrap.customTransferFrom(msg.sender, address(this), _nftId, _amount);
            uint256 idWrap = fundCertWrap.getCurrentId();
            
            Item memory item;
            item.id = id.current();
            item.amount = _amount;
            item.nftId = idWrap - 1;
            item.nftAddress = _nftAddress;
            item.seller = msg.sender;
            item.nftContract = FundCertWrap(_nftAddress);
            items.push(item);
            id.increment();

            emit _eventListNewItemToMarket(item.id, item.nftId, item.amount, item.seller);
        }
    }

    function buyItem(Cart[] calldata cart) external nonReentrant whenMarketOpen {
        for (uint256 i = 0; i < cart.length; i++) {
            Item memory itemSelected = findItemById(cart[i].id);
            address contractAddress = itemSelected.nftAddress;
            fundCertWrap = FundCertWrap(contractAddress);
            require(fundCertWrap.isNotExpired(), "ETF was expired");
            require(cart[i].amount <= itemSelected.amount, "amount item selected must be less than or equal amount item selling");

            uint256 nftPrice = fundCertWrap.getPriceAtTime(block.timestamp);
            uint256 actualValue = nftPrice * cart[i].amount;
            uint256 etherValueFromWei = parseAmountToDecimals(actualValue);
            // payment by amount item
            IERC20(paymentToken).safeTransferFrom(msg.sender, contractAddress, etherValueFromWei);
            // transfer NFT to buyer
            itemSelected.nftContract.customTransferFrom(address(this), msg.sender, itemSelected.nftId, cart[i].amount);

            if(cart[i].amount < itemSelected.amount){
                updateAmountById(cart[i].id, cart[i].amount);
            } else {
                removeItemById(cart[i].id);
            }
            // emit event buy
            emit _eventBuyItemInMarket(itemSelected.id, itemSelected.nftId, cart[i].amount, etherValueFromWei, itemSelected.seller, msg.sender, contractAddress);
        }
    }

    function parseAmountToDecimals(uint256 _amount) view internal returns(uint256) {
        if(decimals == 0){
            return _amount/(1 ether);
        }

        return _amount;
    }

    function delistItem(
        uint256[] memory _ids,
        uint256[] memory _amounts
    ) public {
        require(_ids.length == _amounts.length, "Number item in two array must be the same");
        for (uint i = 0; i < _ids.length; i++) {
            uint256 _id = _ids[i];
            uint256 _amount = _amounts[i];
            Item memory item = findItemById(_id);

            require(item.seller == msg.sender, "not ownerable of this NFT");
            require(_amount <= item.amount, "amount item selected must be less than or equal amount item selling");

            if(_amount == item.amount){
                item.nftContract.customTransferFrom(address(this), item.seller, item.nftId, item.amount);
                removeItemById(_id);
            } else {
                item.nftContract.customTransferFrom(address(this), item.seller, item.nftId, _amount);
                updateAmountById(_id, _amount);
            }
        
            emit _eventDelistItem(item.id, item.nftId, item.amount, item.seller);
        }
    }

    function cleanMarket() public onlyOwner{
        isOpen = false;
        for (uint256 index = 0; index < items.length; index++) {
            items[index].nftContract.customTransferFrom(address(this), items[index].seller, items[index].nftId, items[index].amount);
            removeItemByIndex(index);
        }
    }

    function updateAmountById(uint256 _id, uint256 _sellAmount) internal {
        for (uint i = 0; i < items.length; i++) {
            if(items[i].id == _id){
                items[i].amount -= _sellAmount;
            }
        }
    }

    function removeItemByIndex(uint256 _index) internal {
        items[_index] = items[items.length - 1];
        items.pop();
    }

    function removeItemById(uint256 _id) internal {
        for (uint i = 0; i < items.length; i++) {
            if(items[i].id == _id){
                items[i] = items[items.length - 1];
                items.pop();
            }
        }
    }

    function findItemById(uint256 _id) view internal returns(Item memory) {
        for (uint i = 0; i < items.length; i++) {
            if(items[i].id == _id){
                return items[i];
            }
        }
        
        return items[0];
    }

    function addPublisher(address _publisher) public onlyOwner{
        publishers[_publisher] = true;
    }

    function removePublisher(address _publisher) public onlyOwner{
        publishers[_publisher] = false;
    }

    function setPaymentToken(address _paymentToken, uint256 _decimals) public onlyOwner{
        // validate only set when there are no trading activities
        require(unActivated, "only set when there are no trading activities");
        paymentToken = _paymentToken;
        decimals = _decimals;
    }

    function setMartketStatus(bool _status) public onlyOwner{
        isOpen = _status;
    }

    function getTotalItems() public view returns(uint256) {
        return items.length;
    }

    // this function to contract can receive token ERC1155
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) public pure override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    // this function to contract can recevie token ERC1155
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) public pure override returns (bytes4) {
        revert("batch transfers not supported");
    }
}