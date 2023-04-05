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


interface FundCertOfficialContract {
    struct FundCert {
        uint256 id;
        string name;
        uint256 price;
        uint256 issueDate;
        uint256 expireDate;
        uint256 intervestTerm;
        uint256 totalSupply;
    }

    function getFundCertInfoById(uint256 tokenId) external view returns(FundCert memory);
    function getIntervestTermRate() external view returns(uint256);
    function getBaseRate() external view returns(uint256);
    function getRedeemTime() external view returns(uint256);
    function getPaymentToken() external view returns(address);
    function getIntervestPaymentWallet() external view returns(address);
    function getIntervestRate(uint256 holdingTime) external view returns(uint256);
}

contract FundCertificateWrapped is ERC1155, Ownable, Pausable, ERC1155Burnable, ERC1155Supply, ERC1155Receiver {
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;
    FundCertOfficialContract fundCertOfficialContract;
    Counters.Counter private _fcwId = Counters.Counter(1);

    //parent contract infor
    address public publisher;
    address fundCertOfficial;
    uint256 tokenOfficialId;
    uint256 constant PUBLISHER_TOKEN_WRAPPED_ID = 0;
    uint256 totalFcSupply;
    uint256 unitTime = 1 minutes;
    address creater;

    mapping(address => mapping(uint256 => uint256)) holders;
    mapping(address => mapping(uint256 => Vest[])) userVest;
    mapping(address => NFTSellP2P[]) nftSelling;

    modifier validIssueDate(uint256 _issueDate){
        require(block.timestamp  <= _issueDate, "issue date must be greater than or equal to now");
        _;
    }

    modifier validIntervestTerm(uint256 _interestTerm){
        require(_interestTerm == 90 || _interestTerm == 180, "interest term must be equal to 3 month or 6 month");
        _;
    }

    modifier onlyPublisher(address _user){
        require(_user > publisher, "must be publisher");
        _;
    }

    modifier onlyCreater(address _user) {
        require(_user == fundCertOfficial, "unauthorized");
        _;
    }

    modifier checkExistAndOwner(address _user, uint256 _tokenId){
        require(exists(_tokenId), "NFT not exist");
        require(balanceOf(_user, _tokenId) > 0, "not owner of this tokenId");
        _;
    }

    modifier validateVesting(address _user, uint256 _tokenId){
        Vest[] memory vestlists = userVest[_user][_tokenId];
        bool isMatching = false;
        uint256 currentTime = block.timestamp;
        for (uint256 i = 0; i < vestlists.length; i++) {
            if(
               (currentTime >= vestlists[i].vestDate && currentTime < vestlists[i+1].vestDate || 
                i == (vestlists.length - 1) && currentTime >= vestlists[i].vestDate) &&
                vestlists[i].isVested == false
            ){
                isMatching = true;
            }
        }
        require(isMatching, "token was vested or not in time vested");
        _;
    }

    struct InterestRate {
        uint256 from;
        uint256 to;
        uint256 rate;
    }

    struct Vest {
        uint256 amount;
        bool isVested;
        uint256 vestDate;
        uint256 intervestPayed;
    }

    struct NFTSellP2P {
        address to;
        uint256 tokenId;
        uint256 amount;
        uint256 price;
    }

    event _eventWrapNft(address _publisher, uint256 _tokenId, uint256 _amount, address _contract);
    event _eventListP2P(address _buyer, uint256 _tokenId, uint256 _amount, uint256 _price, uint256 _index, address _contract);
    event _eventBuyWrapNft(address _seller, uint256 _tokenId, uint256 _amount, uint256 _price, uint256 _index, address _contract);
    event _eventSellNow(address _seller, uint256 _tokenId, uint256 _amount, address _contract);

    constructor( 
        uint256 _tokenOfficialId, 
        address _fundCertOfficial, 
        address _publisher,
        uint256 _supply
    ) ERC1155("") {
        tokenOfficialId = _tokenOfficialId;
        fundCertOfficial = _fundCertOfficial;
        publisher = _publisher;
        totalFcSupply = _supply;
        fundCertOfficialContract = FundCertOfficialContract(_fundCertOfficial);
    }

    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }

    function wrap()
        public
        onlyCreater(msg.sender)
        whenNotPaused
    {   
        uint256 intervestTermRate = fundCertOfficialContract.getIntervestTermRate();
        uint256 redeemTime = fundCertOfficialContract.getRedeemTime();
        uint256 baseRate = fundCertOfficialContract.getBaseRate();
        
        // mint CCQWrapped for publisher, rating 10:1 
        _mint(publisher, PUBLISHER_TOKEN_WRAPPED_ID, totalFcSupply, "");
        FundCertOfficialContract.FundCert memory fundInfor = fundCertOfficialContract.getFundCertInfoById(tokenOfficialId);
        uint256 vestingAmount = (((fundInfor.price * 10 * intervestTermRate)/baseRate)/365)*fundInfor.intervestTerm;
        uint256 vestingTime = fundInfor.issueDate;
        for (uint256 index = 0; index < (redeemTime * 30)/fundInfor.intervestTerm; index++) {
            vestingTime += (fundInfor.intervestTerm * (unitTime));
            userVest[publisher][PUBLISHER_TOKEN_WRAPPED_ID].push(Vest(vestingAmount, false, vestingTime, 0));
        }

        // push even wrap
        emit _eventWrapNft(publisher, PUBLISHER_TOKEN_WRAPPED_ID, totalFcSupply, address(this));
    }

    /* user sell nft for publisher */ 
    function sellNow(uint256 tokenId, uint256 amount)
        public
        whenNotPaused
    {   
        address account = msg.sender;
        uint256 timeNow = block.timestamp;
        require(exists(tokenId), "NFT not exist");
        uint256 balance = balanceOf(account, tokenId);
        require(balance > 0, "not owner of this tokenId");
        require(amount <= balance, "number of nft must be less than or equal to balance");

        FundCertOfficialContract.FundCert memory info = fundCertOfficialContract.getFundCertInfoById(tokenOfficialId);

        // burn current NFT of user
        ERC1155Burnable.burn(account, tokenId, amount);
        uint256 currentId = Counters.current(_fcwId);

        // mint new NFT with same amount NFT was burned for publisher
        _mint(publisher, currentId, amount, "");

        // update harvest information
        holders[publisher][currentId] = timeNow;
        userVest[publisher][currentId] = userVest[account][tokenId]; 
        if(balanceOf(account, tokenId) == 0){
            delete holders[account][tokenId];
            delete userVest[account][tokenId];
        }
        // transfer money and profit when sold NFT
        uint256 holdDate = holders[account][tokenId];
        uint256 issueDate = info.issueDate;
        uint256 intervestTerm = info.intervestTerm;
        uint256 basePrice = info.price * 10;
        address paymentToken = fundCertOfficialContract.getPaymentToken();
        uint256 baseRate = fundCertOfficialContract.getBaseRate();
        uint256 profit = 0;
        // case user sell nft in same term
        if((((holdDate - issueDate)/unitTime)/intervestTerm) == (((timeNow - issueDate)/unitTime)/intervestTerm)){
            uint256 price = getPriceAtTime(holdDate);
            uint256 holdingTimes = (timeNow - holdDate)/(unitTime);
            uint256 currentRate = fundCertOfficialContract.getIntervestRate(holdingTimes);
            profit = (((basePrice * currentRate)/baseRate)*holdingTimes)/365;
            IERC20(paymentToken).safeTransfer(account, (price + profit) * amount);
        } 
        // case user sell nft in difference term 
        else {
            uint256 startDate = issueDate + ((((timeNow - issueDate)/unitTime)/intervestTerm) * intervestTerm) * (unitTime);
            uint256 holdingTimes = (timeNow - startDate)/(unitTime);
            uint256 currentRate = fundCertOfficialContract.getIntervestRate(holdingTimes);
            profit = (((basePrice * currentRate)/baseRate)*holdingTimes)/365;
            IERC20(paymentToken).safeTransfer(account, (baseRate + profit) * amount);
        }
        // update intervest paid for trader
        uint256 currentTerm = ((timeNow - issueDate)/unitTime)/intervestTerm;
        userVest[publisher][currentId][currentTerm - 1].intervestPayed += profit;

        Counters.increment(_fcwId);
        emit _eventSellNow(account, tokenId, amount, address(this));
    }

    function getListingP2P() public view returns(NFTSellP2P[] memory) {
        return nftSelling[msg.sender];
    }

    function listP2P(address buyer, uint256 tokenId, uint256 amount, uint256 price) public checkExistAndOwner(msg.sender, tokenId){
        // check amount
        require(balanceOf(msg.sender, tokenId) >= amount, "amount must be less than or equal to balance");
        // transfer nft to contract
        safeTransferFrom(msg.sender, address(this), tokenId, amount, "");

        nftSelling[msg.sender].push(NFTSellP2P(buyer, tokenId, amount, price));

        emit _eventListP2P(buyer, tokenId, amount, price, nftSelling[msg.sender].length - 1, address(this));
    }

    function deListingP2P(uint256 index) public {
        safeTransferFrom(address(this), msg.sender, nftSelling[msg.sender][index].tokenId, nftSelling[msg.sender][index].amount, "");
        uint256 totalItem = nftSelling[msg.sender].length;
        nftSelling[msg.sender][index] = nftSelling[msg.sender][totalItem - 1];
        nftSelling[msg.sender].pop();
    }

    function buyP2P(address seller, uint256 index) public {
        NFTSellP2P memory _nftSellP2P = nftSelling[seller][index];
        require(_nftSellP2P.to == msg.sender, "buyer must be match with seller");
        address paymentToken = fundCertOfficialContract.getPaymentToken();
        IERC20(paymentToken).safeTransferFrom(msg.sender, _nftSellP2P.to, _nftSellP2P.price);

        // burn bo, mint mới
        ERC1155Burnable.burn(address(this), _nftSellP2P.tokenId, _nftSellP2P.amount);
        uint256 currentId = Counters.current(_fcwId);
        _mint(msg.sender, currentId, _nftSellP2P.amount, "");
        holders[msg.sender][currentId] = block.timestamp;
        userVest[msg.sender][currentId] = userVest[seller][_nftSellP2P.tokenId]; 

        if(balanceOf(seller, _nftSellP2P.tokenId) == 0){
            delete holders[seller][_nftSellP2P.tokenId];
            delete userVest[seller][_nftSellP2P.tokenId];
        }

        Counters.increment(_fcwId);
        uint256 totalItem = nftSelling[msg.sender].length;

        //PUSH EVENT buyed to seller
        emit _eventBuyWrapNft(seller, _nftSellP2P.tokenId, _nftSellP2P.amount, _nftSellP2P.price, totalItem - 1, address(this));

        nftSelling[msg.sender][index] = nftSelling[msg.sender][totalItem - 1];
        nftSelling[msg.sender].pop();
    }

    function unWrap()
        public
        whenNotPaused
        onlyPublisher(msg.sender)
    {   
        FundCertOfficialContract.FundCert memory info = fundCertOfficialContract.getFundCertInfoById(tokenOfficialId);
        require(block.timestamp >= info.expireDate, "not in time to redeem");

        uint256 balance = IERC1155(fundCertOfficial).balanceOf(address(this), tokenOfficialId);
        IERC1155(fundCertOfficial).safeTransferFrom(address(this), msg.sender, tokenOfficialId, balance, "");
    }

    // get intervest when intervest term are due
    function harvest(uint256 _tokenId, uint256 _index)
        validateVesting(msg.sender, _tokenId)
        public
    {   
        address account = msg.sender;
        address paymentToken = fundCertOfficialContract.getPaymentToken();
        require(exists(_tokenId), "token id not exist");
        uint256 balance = balanceOf(account, _tokenId);
        require(balance > 0, "not owner of this tokenId");
        
        uint256 currentTime = block.timestamp;
        Vest memory vestItem = userVest[account][_tokenId][_index];
        require(
            currentTime >= vestItem.vestDate && 
            vestItem.isVested == false, 
            "vesting invalid"
        );

        IERC20(paymentToken).safeTransfer(account, balance * vestItem.amount);
        userVest[account][_tokenId][_index].isVested = true;
    }

    function getMyAsset() public view returns(uint256[] memory) {
        uint256[] memory ids;
        uint256 index = 0;
        for(uint256 tokenId = 0; tokenId < _fcwId.current(); tokenId++) { 
            uint256 balance = balanceOf(msg.sender, tokenId);
            if(balance > 0){
                ids[index] = tokenId;
                index += 1;
            }
        }

        return ids;
    }

    function getMyVestList(uint256 _tokenId) public view returns(Vest[] memory){
        return userVest[msg.sender][_tokenId];
    }

    function withdrawIntervest()
        onlyPublisher(msg.sender)
        public
    {   
        address account = msg.sender;
        address paymentToken = fundCertOfficialContract.getPaymentToken();
        for(uint256 tokenId = 0; tokenId < _fcwId.current(); tokenId++) {
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

    // return intervest after users trading
    function getIntervest()
        onlyPublisher(msg.sender)
        public
        view
        returns(uint256)
    {   
        uint256 totalIntervest;
        address account = msg.sender;
        for(uint256 tokenId = 0; tokenId < _fcwId.current(); tokenId++) {
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

    // return price and intervest depend on time in intervest term
    function getPriceAtTime(uint256 _time) public view returns(uint256) {
        FundCertOfficialContract.FundCert memory fundInfor = fundCertOfficialContract.getFundCertInfoById(tokenOfficialId);
        uint256 redeemTime = fundCertOfficialContract.getRedeemTime();
        uint256 intervestTermRate = fundCertOfficialContract.getIntervestTermRate();
        uint256 baseRate = fundCertOfficialContract.getBaseRate();
        uint256 currentTime = _time;
        uint256 basePrice = fundInfor.price * 10;
        for (uint256 index = 1; index <= (redeemTime * 30)/fundInfor.intervestTerm; index++) {
            uint256 startDate = fundInfor.issueDate + (fundInfor.intervestTerm * (index - 1) * unitTime);
            uint256 endDate = fundInfor.issueDate + (fundInfor.intervestTerm * index * unitTime);
            if(currentTime > startDate && currentTime <= endDate){
                uint256 numberDays = (currentTime - startDate)/(unitTime);
                return basePrice + (((basePrice * intervestTermRate)/baseRate)*numberDays)/365;
            }
        }
        
        return basePrice;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function redeem(uint256 tokenId, uint256 amount) public {
        address account = msg.sender;
        FundCertOfficialContract.FundCert memory fundInfor = fundCertOfficialContract.getFundCertInfoById(tokenOfficialId);
        uint256 expireDate = fundInfor.expireDate;
        require(block.timestamp >= expireDate, "not in redeem time");
        address paymentToken = fundCertOfficialContract.getPaymentToken();

        // receive NFT
        IERC1155(fundCertOfficial).safeTransferFrom(account, publisher, tokenId, amount, "");
        // refund to user
        IERC20(paymentToken).safeTransfer(account, fundInfor.price * 10);
    }

    function getRootId() public view returns(uint256) {
        return tokenOfficialId;
    }

    function getCurrentId() public view returns(uint256) {
        return _fcwId.current();
    }

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
        if(from != address(0)){
            for (uint256 i = 0; i < ids.length; i++) {
                ERC1155Burnable.burn(from, ids[i], amounts[i]);
                uint256 currentId = Counters.current(_fcwId);
                _mint(to, currentId, amounts[i], data);
                
                holders[to][currentId] = block.timestamp;
                userVest[to][currentId] = userVest[from][ids[i]]; 

                if(balanceOf(from, ids[i]) == 0){
                    delete holders[to][ids[i]];
                    delete userVest[to][ids[i]];
                }
                Counters.increment(_fcwId);
            }
        }
    }
}