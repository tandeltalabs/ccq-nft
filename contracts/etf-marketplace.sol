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
   
    struct Item {
        uint256 id;
        uint256 nftId;
        address nftAddress;
        uint256 amount;
        address seller;
        FundCertWrap nftContract;
    }

    struct Cart {
        uint256 index;
        uint256 amount;
    }

    Item[] public items;

    constructor(address _paymentToken, bool _isOpen) {
        paymentToken = _paymentToken;
        isOpen = _isOpen;
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
    event _eventBuyItemInMarket(uint256 id, uint256 nftId, uint256 amount, uint256 totalValue, address seller, address buyer);

    function sellItem(
        address _nftAddress,
        uint256 _nftId,
        uint256 _amount
    ) whenMarketOpen onlyPublisher(msg.sender) public {
        fundCertWrap = FundCertWrap(_nftAddress);
        require(fundCertWrap.isNotExpired(), "ETF was expired");

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

    function buyItem(Cart[] calldata cart) external nonReentrant whenMarketOpen {
        for (uint256 i = 0; i < cart.length; i++) {
            Item memory itemSelected = items[cart[i].index];
           
            fundCertWrap = FundCertWrap(itemSelected.nftAddress);
            require(fundCertWrap.isNotExpired(), "ETF was expired");
            require(cart[i].amount <= itemSelected.amount, "amount item selected must be less than or equal amount item selling");

            uint256 nftPrice = fundCertWrap.getPriceAtTime(block.timestamp);
            uint256 actualValue = nftPrice * cart[i].amount;
            uint256 etherValueFromWei = actualValue/(1 ether);
            // payment by amount item
            IERC20(paymentToken).safeTransferFrom(msg.sender, itemSelected.nftAddress, etherValueFromWei);
            // transfer NFT to buyer
            itemSelected.nftContract.customTransferFrom(address(this), msg.sender, itemSelected.nftId, cart[i].amount);
            if(cart[i].amount < itemSelected.amount){
                items[cart[i].index].amount -= cart[i].amount;
            } else {
                removeItemByIndex(cart[i].index);
            }
            // emit event buy
            emit _eventBuyItemInMarket(itemSelected.id, itemSelected.nftId, cart[i].amount, etherValueFromWei, itemSelected.seller, msg.sender);
        }
    }

    function delistItem(
        uint256 _index,
        uint256 _amount
    ) public {
        Item memory item = items[_index];
        require(item.seller == msg.sender, "not ownerable of this NFT");
        require(_amount <= item.amount, "amount item selected must be less than or equal amount item selling");
        if(_amount == item.amount){
            item.nftContract.customTransferFrom(address(this), item.seller, item.nftId, item.amount);
            removeItemByIndex(_index);
        } else {
            item.nftContract.customTransferFrom(address(this), item.seller, item.nftId, _amount);
            items[_index].amount -= _amount;
        }
       
        emit _eventDelistItem(item.id, item.nftId, item.amount, item.seller);
    }

    function cleanMarket() public onlyOwner{
        isOpen = false;
        for (uint256 index = 0; index < items.length; index++) {
            items[index].nftContract.customTransferFrom(address(this), items[index].seller, items[index].nftId, items[index].amount);
            removeItemByIndex(index);
        }
    }

    function removeItemByIndex(uint256 _index) internal {
        items[_index] = items[items.length - 1];
        items.pop();
    }

    function addPublisher(address _publisher) public onlyOwner{
        publishers[_publisher] = true;
    }

    function removePublisher(address _publisher) public onlyOwner{
        publishers[_publisher] = false;
    }

    function setPaymentToken(address _paymentToken) public onlyOwner{
        paymentToken = _paymentToken;
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