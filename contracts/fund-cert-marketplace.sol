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
    function getPriceAtTime(uint256 time) external view returns(uint256);
    function getRootId() external view returns(uint256);
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
        uint256 rootId;
        address nftAddress;
        uint256 amount;
        address seller;
        IERC1155 nftContract;
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

    event listNewItemToMarket(uint256 id, uint256 nftId, uint256 amount, address seller);
    event buyItemToMarket(uint256 id, uint256 nftId, uint256 amount, address seller, address buyer);

    function sellItem(
        address _nftAddress,
        uint256 _nftId,
        uint256 _amount
    ) whenMarketOpen onlyPublisher(msg.sender) public {
        IERC1155(_nftAddress).safeTransferFrom(msg.sender, address(this), _nftId, _amount, "");
        fundCertWrap = FundCertWrap(_nftAddress);
        Item memory item;
        item.id = id.current();
        item.amount = _amount;
        item.rootId = fundCertWrap.getRootId();
        item.nftId = _nftId;
        item.nftAddress = _nftAddress;
        item.seller = msg.sender;
        item.nftContract = IERC1155(_nftAddress);
        items.push(item);
        id.increment();

        emit listNewItemToMarket(item.id, item.nftId, item.amount, item.seller);
    }

    function buyItem(
        uint256 _index,
        uint256 _amount
    ) external nonReentrant whenMarketOpen {
        Item memory itemSelected = items[_index];
        require(_amount <= itemSelected.amount, "amount item selected must be less than or equal amount item selling");
        // get current Price
        fundCertWrap = FundCertWrap(itemSelected.nftAddress);
        uint256 nftPrice = fundCertWrap.getPriceAtTime(block.timestamp);
        // payment by amount item
        IERC20(paymentToken).transferFrom(msg.sender, itemSelected.nftAddress, nftPrice * _amount);
        // transfer NFT to buyer
        itemSelected.nftContract.safeTransferFrom(address(this), msg.sender, itemSelected.nftId, _amount, "");

        if(_amount < itemSelected.amount){
            items[_index].amount -= _amount;
        } else {
            removeItemByIndex(_index);
        }
        // emit event buy
        emit buyItemToMarket(itemSelected.id, itemSelected.nftId, _amount, itemSelected.seller, msg.sender);
    }

    function delistItem(
        address _nftAddress,
        uint256 _nftId
    ) public {
        for (uint256 index = 0; index < items.length; index++) {
            if(items[index].nftAddress == _nftAddress && items[index].nftId == _nftId){
                require(items[index].seller == msg.sender, "user must be nft owner");
                items[index].nftContract.safeTransferFrom(address(this), items[index].seller, items[index].nftId, items[index].amount, "");
                removeItemByIndex(index);
            }
        }
    }

    function cleanMarket() public onlyOwner{
        isOpen = false;
        for (uint256 index = 0; index < items.length; index++) {
            items[index].nftContract.safeTransferFrom(address(this), items[index].seller, items[index].nftId, items[index].amount, "");
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
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) public override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) public override returns (bytes4) {
        revert("batch transfers not supported");
    }
}