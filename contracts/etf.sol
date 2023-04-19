// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Receiver.sol";

contract FundGoETFWrapped is ERC1155, Ownable, Pausable, ERC1155Burnable, ERC1155Supply, ERC1155Receiver {
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;
    Counters.Counter private _fcwId = Counters.Counter(1);
    Counters.Counter private _orderId = Counters.Counter(1);

    struct InterestRate {
        uint256 from;
        uint256 to;
        uint256 rate;
    }

    struct PriceSellNow {
        uint256 price;
        uint256 profit;
        uint256 rate;
        uint256 holdingTime;
    }

    struct Vest {
        uint256 amount;
        bool isVested;
        uint256 vestDate;
        uint256 intervestPayed;
    }

    struct NFTTradeP2P {
        uint256 orderId;
        address user; // isSelling == false: user => seller, isSelling == true: user => buyer
        bool isSelling; 
        uint256 tokenId;
        uint256 sellDate;
        uint256 amount;
        uint256 price;
    }

    struct ETFInformation {
        address publisher;
        string name;
        uint256 price;
        uint256 issueDate;
        uint256 expireDate;
        uint256 intervestTerm;
        uint256 totalSupply;
    }

    
    uint256 constant PUBLISHER_TOKEN_WRAPPED_ID = 0;
    uint256 unitTime = 1 minutes;
    address public paymentToken;
    address public marketplace;
    uint256 public baseRate = 1000;
    uint256 public numberTerm = 5;
    uint256 public intervestTermRate = 80; 
    uint256 public totalAdvanceIntervest;
    uint256 public totalIntervestPayed;
    uint256 public onceTermIntervest;

    InterestRate[] interestRate;
    ETFInformation public etfInfor;
    mapping(address => bool) whitelists;
    mapping(address => mapping(uint256 => uint256)) holders;
    mapping(address => mapping(uint256 => Vest[])) userVest;
    mapping(address => NFTTradeP2P[]) orderP2P;
    mapping(address => uint256[]) tokensOwned;
    mapping(address => mapping(uint256 => bool)) intervestHistory;
    mapping(address => mapping(uint256 => bool)) intervestTempHistory;
    
    constructor( 
        address _publisher,
        string memory _name, 
        uint256 _issueDate, 
        uint256 _totalSupply, 
        uint256 _intervestTerm, 
        uint256 _price,
        address _paymentToken,
        address _marketplace
    ) ERC1155("") {
        paymentToken = _paymentToken;
        marketplace = _marketplace;

        etfInfor.publisher = _publisher;
        etfInfor.name = _name;
        etfInfor.issueDate = _issueDate;
        etfInfor.expireDate = _issueDate + numberTerm * _intervestTerm * unitTime;
        etfInfor.intervestTerm = _intervestTerm;
        etfInfor.price = _price * 1 ether;
        etfInfor.totalSupply = _totalSupply;

        onceTermIntervest = (_totalSupply*(((_price * 1 ether * intervestTermRate)/baseRate) * _intervestTerm)/365)/(1 ether);

        interestRate.push(InterestRate(1, 14, 60));
        interestRate.push(InterestRate(15, 29, 70));
        interestRate.push(InterestRate(30, 92, 80));
        
        mint(_publisher, _issueDate, _intervestTerm, _price * 1 ether, _totalSupply);
    }

    modifier validIssueDate(uint256 _issueDate){
        require(block.timestamp  <= _issueDate, "issue date must be greater than or equal to now");
        _;
    }

    modifier onlyExpireDate(){
        require(block.timestamp >= etfInfor.expireDate , "undue");
        _;
    }

    modifier whenNotExpired(){
        require(block.timestamp < etfInfor.expireDate , "ETF was expired");
        _;
    }

    modifier onlyPublisher(address _user){
        require(_user > etfInfor.publisher, "must be publisher");
        _;
    }

    modifier checkExistAndOwner(address _user, uint256 _tokenId){
        require(exists(_tokenId), "NFT not exist");
        require(balanceOf(_user, _tokenId) > 0, "not owner of this tokenId");
        _;
    }

    event _eventListP2P(address _seller, address _buyer, uint256 _tokenId, uint256 _amount, uint256 _totalValue, uint256 _orderId);
    event _eventDeListP2P(address _seller, address _buyer, uint256 _tokenId, uint256 _amount, uint256 _totalValue, uint256 _orderId);
    event _eventBuyP2P(address _seller, address _buyer, uint256 _tokenId, uint256 _amount,uint256 _totalValue, uint256 _orderId, uint256 _holdingTime);
    event _eventSellNow(address _seller, address _buyer, uint256 _tokenId, uint256 _amount, uint256 _totalValue, uint256 _holdingTime);

    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }

    function mint(
        address _publisher,
        uint256 _issueDate,
        uint256 _intervestTerm,
        uint256 _price,
        uint256 _totalSupply
    )
        internal
    {   
        _mint(_publisher, PUBLISHER_TOKEN_WRAPPED_ID, _totalSupply, "");
        
        tokensOwned[_publisher].push(PUBLISHER_TOKEN_WRAPPED_ID);
        holders[_publisher][PUBLISHER_TOKEN_WRAPPED_ID] = block.timestamp;
        uint256 vestingAmount = (((_price * intervestTermRate)/baseRate)*_intervestTerm)/365;
        uint256 parsedValue = etherFromWei(vestingAmount);
        uint256 vestingTime =_issueDate;
        for (uint256 index = 0; index < numberTerm; index++) {
            vestingTime += (_intervestTerm * (unitTime));
            userVest[_publisher][PUBLISHER_TOKEN_WRAPPED_ID].push(Vest(parsedValue, false, vestingTime, 0));
        }

        // push even wrap
    }

    /* user sell nft for publisher */ 
    function sellNow(uint256 tokenId, uint256 amount)
        public
        whenNotPaused
        whenNotExpired
    {   
        uint256 timeNow = block.timestamp;
        require(exists(tokenId), "NFT not exist");
        uint256 balance = balanceOf(msg.sender, tokenId);
        require(balance > 0, "not owner of this tokenId");
        require(amount <= balance, "number of nft must be less than or equal to balance");

        // burn current NFT of user
        ERC1155Burnable.burn(msg.sender, tokenId, amount);
        uint256 currentId = Counters.current(_fcwId);

        // mint new NFT with same amount NFT was burned for publisher
        _mint(etfInfor.publisher, currentId, amount, "");

        // update harvest information
        holders[etfInfor.publisher][currentId] = timeNow;
        userVest[etfInfor.publisher][currentId] = userVest[msg.sender][tokenId];
        tokensOwned[etfInfor.publisher].push(currentId);

        if(balance == amount){
            removeByTokenId(msg.sender, tokenId);
            delete holders[msg.sender][tokenId];
            delete userVest[msg.sender][tokenId];
        }
        // transfer money and profit when sold NFT
        uint256 issueDate = etfInfor.issueDate;
        uint256 intervestTerm = etfInfor.intervestTerm;
        uint256 totalAmount = 0;
        PriceSellNow memory priceSellNow = getPriceWhenSellNow(msg.sender, tokenId);
        totalAmount = (priceSellNow.price + priceSellNow.profit) * amount;
        uint256 parsedValue = etherFromWei(totalAmount);

        IERC20(paymentToken).safeTransfer(msg.sender, parsedValue);

        // update intervest paid for trader
        unchecked {
            uint256 duringETF = (block.timestamp - issueDate)/unitTime;
            uint256 currentTerm = duringETF/intervestTerm;
            uint256 remindNumber = duringETF%intervestTerm;

            if(remindNumber > 0){
                currentTerm += 1;
            }
        
            if(currentTerm > 0 && etherFromWei(priceSellNow.profit) > 0){
                userVest[etfInfor.publisher][currentId][currentTerm - 1].intervestPayed += etherFromWei(priceSellNow.profit);
            }
        }

        Counters.increment(_fcwId);
        emit _eventSellNow(msg.sender, etfInfor.publisher, tokenId, amount, parsedValue, priceSellNow.holdingTime);
    }

    function getPriceWhenSellNow(address _user, uint256 _tokenId) public view returns(PriceSellNow memory) {
        uint256 holdDate = holders[_user][_tokenId];
        uint256 issueDate = etfInfor.issueDate;
        uint256 intervestTerm = etfInfor.intervestTerm;
        uint256 basePrice = etfInfor.price;
        uint256 profit = 0;
        uint256 actuallyAmount = 0;
        uint256 holdingTime;
        uint256 rate;
        unchecked {
            uint256 etfTimeFromNow = (block.timestamp - issueDate)/unitTime;
            // case user sell nft in in term 
            if((((holdDate - issueDate)/unitTime)/intervestTerm) == (etfTimeFromNow/intervestTerm)){
                uint256 price = getPriceAtTime(holdDate);
                holdingTime = (block.timestamp - holdDate)/(unitTime);
                rate = getIntervestRate(holdingTime);
                profit = (((basePrice * rate)/baseRate)*holdingTime)/365;
                actuallyAmount = price;
            } 
            // case user sell nft in difference term 
            else {
                uint256 startDate = issueDate + ((etfTimeFromNow/intervestTerm) * intervestTerm) * (unitTime);
                holdingTime = (block.timestamp - startDate)/(unitTime);
                rate = getIntervestRate(holdingTime);
                profit = (((basePrice * rate)/baseRate)*holdingTime)/365;
                actuallyAmount = basePrice;
            }
        }
       
        PriceSellNow memory priceSellNow = PriceSellNow(actuallyAmount, profit, rate, holdingTime);

        return priceSellNow;
    }

    function getListingP2P(address _user) public view returns(NFTTradeP2P[] memory) {
        return orderP2P[_user];
    }

    function listP2P(address buyer, uint256 tokenId, uint256 amount, uint256 price) public 
        checkExistAndOwner(msg.sender, tokenId)
        whenNotExpired
    {
        address seller = msg.sender;
        // check amount
        require(balanceOf(seller, tokenId) >= amount, "amount must be less than or equal to balance");
        // transfer nft to contract
        uint256 orderId = _orderId.current();

        safeTransferFrom(seller, address(this), tokenId, amount, "");

        orderP2P[seller].push(NFTTradeP2P(orderId, buyer, true, tokenId, block.timestamp, amount, price));
        orderP2P[buyer].push(NFTTradeP2P(orderId, seller, false, tokenId, block.timestamp, amount, price));

        _orderId.increment();

        emit _eventListP2P(seller, buyer, tokenId, amount, amount * price, orderId);
    }

    function deListingP2P(uint256 orderId) public {
        address user = msg.sender;
        NFTTradeP2P memory currentUserItem = findItemP2PItem(user, orderId);
        require(orderId > 0, "order not found");
        address otherUser = currentUserItem.user;
        uint256 tokenId = currentUserItem.tokenId;
        uint256 amount = currentUserItem.amount;
        bool isSelling = currentUserItem.isSelling;

        if(isSelling){
            _safeTransferFrom(address(this), user, tokenId, amount, "");
            emit _eventDeListP2P(user, currentUserItem.user, tokenId, amount, currentUserItem.price, orderId);
        } else {
            _safeTransferFrom(address(this), currentUserItem.user, tokenId, amount, "");
            emit _eventDeListP2P(currentUserItem.user, user, tokenId, amount, currentUserItem.price, orderId);
        }

        // remove order item
        removeItemP2PItem(user, orderId);
        removeItemP2PItem(otherUser, orderId);
    }

    function findItemP2PItem(address _user, uint256 _id) public view returns(NFTTradeP2P memory){
        for(uint256 i = 0; i < orderP2P[_user].length; i++) { 
            if(orderP2P[_user][i].orderId == _id){
                NFTTradeP2P memory found = orderP2P[_user][i];
                return found;
            }
        }
        NFTTradeP2P memory nullOrder;
        return nullOrder;
    }

    function removeItemP2PItem(address _user, uint256 _id) internal {
        uint256 totalItem = orderP2P[_user].length;
        for(uint256 i = 0; i < totalItem; i++) { 
            if(orderP2P[_user][i].orderId == _id){
                orderP2P[_user][i] = orderP2P[_user][totalItem - 1];
                orderP2P[_user].pop();
                break;
            }
        }
    }

    function buyP2P(uint256 orderId) 
        public 
        whenNotExpired
    {
        address buyer = msg.sender;
        NFTTradeP2P memory buyItem = findItemP2PItem(buyer, orderId);
        require(buyItem.orderId > 0, "order not found");
        address seller = buyItem.user;
        // payment
        IERC20(paymentToken).safeTransferFrom(buyer, seller, buyItem.price);
        // transfer etf
        _burn(address(this), buyItem.tokenId, buyItem.amount);
        uint256 currentId = Counters.current(_fcwId);
        _mint(buyer, currentId, buyItem.amount, "");
        // update information
        holders[buyer][currentId] = block.timestamp;
        userVest[buyer][currentId] = userVest[seller][buyItem.tokenId]; 
        tokensOwned[buyer].push(currentId);
        uint256 holdingTime;
        unchecked {
            holdingTime = (block.timestamp - holders[seller][buyItem.tokenId])/unitTime;
        }

        if(balanceOf(seller, buyItem.tokenId) == 0){
            removeByTokenId(seller, buyItem.tokenId);
            delete holders[seller][buyItem.tokenId];
            delete userVest[seller][buyItem.tokenId];
        }

        //remove order
        removeItemP2PItem(seller, orderId);
        removeItemP2PItem(buyer, orderId);

        Counters.increment(_fcwId);

        //push event buyed
        emit _eventBuyP2P(seller, buyer, currentId, buyItem.amount, buyItem.price, orderId, holdingTime);
    }

    // get intervest when intervest term are due
    function harvest(uint256 _tokenId, uint256 _index)
        checkExistAndOwner(msg.sender, _tokenId)
        public
    {      
        address account = msg.sender;
        Vest memory vestItem = userVest[account][_tokenId][_index];
        uint256 balance = balanceOf(account, _tokenId);

        require(
            block.timestamp >= vestItem.vestDate && 
            vestItem.isVested == false && 
            vestItem.amount > 0, 
            "token was vested or not in time vested"
        );

        IERC20(paymentToken).safeTransfer(account, balance * vestItem.amount);
        userVest[account][_tokenId][_index].isVested = true;
    }

    function getMyAsset(address _user) public view returns(uint256[] memory) {
        return tokensOwned[_user];
    }

    function getMyVestList(address _user, uint256 _tokenId) public view returns(Vest[] memory){
        return userVest[_user][_tokenId];
    }

    function withdrawIntervest()
        onlyPublisher(msg.sender)
        public
    {   
        address account = msg.sender;
        for(uint256 index = 0; index < tokensOwned[msg.sender].length; index++) {
            uint256 tokenId = tokensOwned[msg.sender][index];
            uint256 balance = balanceOf(account, tokenId);
            if(balance > 0){
                Vest[] memory vestlists = userVest[account][tokenId];
                uint256 currentTime = block.timestamp;
                for (uint256 i = 0; i < vestlists.length; i++) {
                    if(
                        (currentTime >= vestlists[i].vestDate && currentTime < vestlists[i+1].vestDate || 
                        i == (vestlists.length - 1) && currentTime >= vestlists[i].vestDate) &&
                        vestlists[i].isVested == false
                    ){
                        uint256 intervest = (balance * vestlists[i].amount) - vestlists[i].intervestPayed;
                        IERC20(paymentToken).safeTransfer(account, intervest);
                        userVest[account][tokenId][i].isVested = true;
                    }
                }
            }
        }
    }

    function payIntervest(uint256 _paymentDate) public {
        IERC20(paymentToken).safeTransferFrom(msg.sender, address(this), onceTermIntervest);
        totalIntervestPayed += onceTermIntervest;
        intervestHistory[msg.sender][_paymentDate] = true;
    }

    function payAdvanceIntervest(uint256 _paymentDate) public {
        IERC20(paymentToken).safeTransferFrom(msg.sender, address(this), onceTermIntervest);
        totalAdvanceIntervest += onceTermIntervest;
        intervestTempHistory[msg.sender][_paymentDate] = true;
    }

    function withdrawAdvanceIntervest() public onlyPublisher(msg.sender) onlyExpireDate {
        require(totalIntervestPayed == (onceTermIntervest * numberTerm), "issuer need payment all of intervest");
        IERC20(paymentToken).safeTransfer(msg.sender, totalAdvanceIntervest);
        totalAdvanceIntervest = 0;
    }

    // return intervest after users trading
    function getIntervest()
        onlyPublisher(msg.sender)
        public
        view
        returns(uint256)
    {   
        uint256 totalIntervest;
        address account = msg.sender;
        for(uint256 index = 0; index < tokensOwned[msg.sender].length; index++) {
            uint256 tokenId = tokensOwned[msg.sender][index];
            uint256 balance = balanceOf(account, tokenId);
            if(balance > 0){
                Vest[] memory vestlists = userVest[account][tokenId];
                uint256 currentTime = block.timestamp;
                for (uint256 i = 0; i < vestlists.length; i++) {
                    if(
                        (currentTime >= vestlists[i].vestDate && currentTime < vestlists[i+1].vestDate || 
                        i == (vestlists.length - 1) && currentTime >= vestlists[i].vestDate) &&
                        vestlists[i].isVested == false
                    ){
                        uint256 intervest = (balance * vestlists[i].amount) - vestlists[i].intervestPayed;
                        totalIntervest += intervest;
                    }
                }
            }
        }

        return totalIntervest;
    }

    function isIntervestPayed(address _user, uint256 _paymentDate) public view returns(bool) {
        return intervestHistory[_user][_paymentDate];
    }

    function isAdvanceIntervestPayed(address _user, uint256 _paymentDate) public view returns(bool) {
        return intervestTempHistory[_user][_paymentDate];
    }

    // return price and intervest depend on time in intervest term
    function getPriceAtTime(uint256 _time) public view returns(uint256) {
        uint256 currentTime = _time;
        uint256 basePrice = etfInfor.price;
        for (uint256 index = 1; index <= numberTerm; index++) {
            uint256 startDate = etfInfor.issueDate + (etfInfor.intervestTerm * (index - 1) * unitTime);
            uint256 endDate = etfInfor.issueDate + (etfInfor.intervestTerm * index * unitTime);

            if(currentTime > startDate && currentTime <= endDate){
                uint256 numberDays = (currentTime - startDate)/(unitTime);
                return basePrice + (((basePrice * intervestTermRate)/baseRate)*numberDays)/365;
            }
        }

        return basePrice;
    }

    function redeem(uint256 tokenId, uint256 amount) public {
        address account = msg.sender;
        require(block.timestamp >= etfInfor.expireDate, "not in redeem time");
        // burn nft
        safeTransferFrom(account, address(this), tokenId, amount, "");
        
        removeByTokenId(account, tokenId); 
        delete holders[account][tokenId];
        delete userVest[account][tokenId];
        uint256 totalValue = etfInfor.price * amount;
        uint256 parsedValue = etherFromWei(totalValue);
        // refund to user
        IERC20(paymentToken).safeTransfer(account, parsedValue);
    }

    function getCurrentId() public view returns(uint256) {
        return _fcwId.current();
    }

    function getIntervestRate(uint256 holdingTime) public view returns(uint256){
        uint256 rate = 0;
        for (uint256 index = 0; index < interestRate.length; index++) {
            if(holdingTime >= interestRate[index].from && holdingTime <= interestRate[index].to){
                rate = interestRate[index].rate;
                break;
            }
        }
        return rate;
    }

    function getHoldingDate(address _user, uint256 _id) public view returns(uint256) {
        return holders[_user][_id];
    }

    function removeByTokenId(address _user, uint256 _id) internal {
        uint256 totalItem = tokensOwned[_user].length;
        for (uint256 index = 0; index < totalItem; index++) {
            if(tokensOwned[_user][index] == _id){
                tokensOwned[_user][index] = tokensOwned[_user][totalItem - 1];
                tokensOwned[_user].pop();
                break;
            }
        }
    }

    function setInterestRate(InterestRate[] memory _interestRate) public onlyOwner {
        delete interestRate;
        for (uint256 index = 0; index < _interestRate.length; index++) {
            interestRate.push(_interestRate[index]);
        }
    }

    function setMarketplace(address _marketplace) public onlyOwner {
        marketplace = _marketplace;
    }

    function setIntervestTermRate(uint256 _intervestTermRate) public onlyOwner {
        intervestTermRate = _intervestTermRate;
    }

     function etherFromWei(uint256 _etherValue) pure internal returns(uint256) {
        return _etherValue/(1 ether);
    }

    function isNotExpired() public view returns(bool) {
        bool notExpired = true;
        if(block.timestamp >= etfInfor.expireDate){
            notExpired = false;
        }
        return notExpired;
    }

    function customTransferFrom(address from, address to, uint256 id, uint256 amount) public {
        require(msg.sender == marketplace, "caller must be from market");

        uint256 currentId = Counters.current(_fcwId);
        uint256 balanceFrom = balanceOf(from, id);

        require(balanceFrom >= amount, "ERC1155: insufficient balance for transfer");

        _burn(from, id, amount);

        _mint(to, currentId, amount, "");
        
        tokensOwned[to].push(currentId);
        holders[to][currentId] = block.timestamp;
        userVest[to][currentId] = userVest[from][id];

        if(balanceFrom == amount){
            removeByTokenId(from, id); 
            delete holders[from][id];
            delete userVest[from][id];
        }

        Counters.increment(_fcwId);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    // this function to contract can recevie token ERC1155
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

    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        override(ERC1155, ERC1155Receiver) 
        returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || super.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        internal
        whenNotPaused
        override(ERC1155, ERC1155Supply)
    {
        require(from == address(0) || to == address(0) || to == address(this) || from == address(this), "this NFT only trade with this contract");
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }
}