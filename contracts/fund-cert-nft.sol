// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

interface FundCertProvider {
    function createContract(address owner, uint256 tokenId, address contractFC, address publisher, uint256 amount) external;
    function getContractAddress(uint256 tokenId) external view returns(address);
}
interface FundCertWrap {
    function wrap() external;
}
contract FundCertificate is ERC1155, Ownable, Pausable, ERC1155Burnable, ERC1155Supply{
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;
    using EnumerableMap for EnumerableMap.UintToAddressMap;
    using EnumerableMap for EnumerableMap.UintToUintMap;
    FundCertProvider fundCertProvider;
    Counters.Counter private _issueIdCounter;


    uint256 baseRate = 1000;
    uint256 redeemTime = 4;
    uint256 intervestTermRate = 80; 
    address paymentToken;

    struct InterestRate {
        uint256 from;
        uint256 to;
        uint256 rate;
    }

    struct FundCert {
        uint256 id;
        string name;
        uint256 price;
        uint256 issueDate;
        uint256 expireDate;
        uint256 intervestTerm;
        uint256 totalSupply;
    }

    struct TokenOwner {
        uint256 id;
        address publisher;
    }

    struct IntervestPayment {
        uint256 id;
        uint256 number;
        bool paid;
        address contractWrap;
        uint256 expireDate;
        uint256 amount;
    }

    InterestRate[] interestRates;
    TokenOwner[] public tokenOwner;

    mapping(address => bool) whitelists;
    mapping(uint256 => FundCert) issueCert;
    mapping(uint256 => IntervestPayment[]) intervestPaymentMap;
    mapping(uint256 => IntervestPayment[]) intervestPaymentMapTemp;

    modifier onlyInWhitelist(address _issuer){
        require(whitelists[_issuer] || _issuer == owner(), "user must be in whitelist");
        _;
    }
     
    modifier validIssueDate(uint256 _issueDate){
        require(block.timestamp  <= _issueDate, "issue date must be greater than or equal to now");
        _;
    }
    
    constructor(address _paymentToken, address _provider) ERC1155("https://example.com/token/") {
        paymentToken = _paymentToken;
        interestRates.push(InterestRate(1, 14, 60));
        interestRates.push(InterestRate(15, 29, 70));
        interestRates.push(InterestRate(30, 180, 80));
        fundCertProvider = FundCertProvider(_provider);
    }

    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function issue(
        address account,
        string memory name, 
        uint256 issueDate, 
        uint256 totalSuply, 
        uint256 intervestTerm, 
        uint256 price)
        public
        onlyInWhitelist(msg.sender)
        validIssueDate(issueDate)
    {   
        uint256 id = _issueIdCounter.current();
        // set nft infor
        FundCert memory fundCertInfo;
        fundCertInfo.id = id;
        fundCertInfo.name = name;
        fundCertInfo.issueDate = issueDate;
        fundCertInfo.expireDate = issueDate + redeemTime * 30 minutes;
        fundCertInfo.intervestTerm = intervestTerm;
        fundCertInfo.price = price;
        fundCertInfo.totalSupply = totalSuply;
        issueCert[id] = fundCertInfo;

        // create contract wrap
        address _publisherAddress = account;
        fundCertProvider.createContract(msg.sender, id, address(this), _publisherAddress, totalSuply/10);
        address fcWrap = fundCertProvider.getContractAddress(id);
        // mint token to wrap contract
        _mint(fcWrap, id, totalSuply, "");
        // wrap 
        FundCertWrap(fcWrap).wrap();
        // set invervest term
        calculateIntervestByTerm(id, intervestTerm, issueDate, price, fcWrap);

        tokenOwner.push(TokenOwner(id, account));
        _issueIdCounter.increment();

    }

    function calculateIntervestByTerm(uint256 id, uint256 intervestTerm, uint256 issueDate, uint256 price, address fcWrap) internal {
        uint256 vestingAmount = (((price * 10 * intervestTermRate)/baseRate)*intervestTerm)/365;
        uint256 vestingTime = issueDate;

        uint256 totalTerm = (redeemTime * 30)/intervestTerm;
        for (uint256 index = 0; index < totalTerm; index++) {
            vestingTime += (intervestTerm * 1 minutes);
            IntervestPayment memory _intervestPayment = IntervestPayment(id, index, false, fcWrap, vestingTime, vestingAmount);
            intervestPaymentMap[id].push(_intervestPayment);
        }

        intervestPaymentMapTemp[id] = intervestPaymentMap[id];
    }

    function payIntervest(uint256 tokenId, uint256 invoiceNumber) public onlyOwner {
        address fcWrap = fundCertProvider.getContractAddress(tokenId);
        for (uint256 index = 0; index < intervestPaymentMap[tokenId].length; index++) {
            IntervestPayment memory _intervestPayment = intervestPaymentMap[tokenId][index];
            if(_intervestPayment.number == invoiceNumber){
                require(!_intervestPayment.paid, "invoice was paid");
                IERC20(paymentToken).safeTransferFrom(msg.sender, fcWrap, _intervestPayment.amount);
                intervestPaymentMap[tokenId][index].paid = true;
                break;
            }
        }
    }

    function payIntervestTemp(uint256 tokenId, uint256 invoiceNumber) public {
        address fcWrap = fundCertProvider.getContractAddress(tokenId);
        for (uint256 index = 0; index < intervestPaymentMapTemp[tokenId].length; index++) {
            IntervestPayment memory _intervestPayment = intervestPaymentMapTemp[tokenId][index];
            if(_intervestPayment.number == invoiceNumber){
                require(!_intervestPayment.paid, "invoice was paid");
                IERC20(paymentToken).safeTransferFrom(msg.sender, fcWrap, _intervestPayment.amount);
                intervestPaymentMapTemp[tokenId][index].paid = true;
                break;
            }
        }
    } 

    function getFundCertInfoById(uint256 tokenId) public view virtual returns(FundCert memory){
        return issueCert[tokenId];
    }

    function getIntervestTermRate() public view returns(uint256){
        return intervestTermRate;
    }

    function getBaseRate() public view returns(uint256){
        return baseRate;
    }

    function setBaseRate(uint256 _baseRate) public onlyOwner {
        baseRate = _baseRate;
    }

    function getRedeemTime() public view returns(uint256){
        return redeemTime;
    }

    function setRedeemTime(uint256 _redeemTime) public onlyOwner{
        redeemTime = _redeemTime;
    }

    function getIntervestRate(uint256 holdingTime) public view returns(uint256){
        for (uint256 index = 0; index < interestRates.length; index++) {
            if(holdingTime >= interestRates[index].from && holdingTime <= interestRates[index].to){
                return interestRates[index].rate;
            }
        }
        return interestRates[0].rate;
    }

    function getInterestRates() public view returns(InterestRate[] memory){
        return interestRates;
    }

    function setInterestRates(InterestRate[] calldata _interestRates) public onlyOwner{
        delete interestRates;
        for (uint256 index = 0; index < _interestRates.length; index++) {
            interestRates.push(_interestRates[index]);
        }
    }
       
    function getPaymentToken() public view returns(address){
        return paymentToken;
    }

    function setPaymentToken(address _paymentToken) public onlyOwner {
        paymentToken = _paymentToken;
    }

    function isWhitelist(address walletAddress) public view returns(bool){
        return whitelists[walletAddress];
    }

    function setWhitelist(address[] calldata _whitelists) public onlyOwner {
        for (uint256 index = 0; index < _whitelists.length; index++) {
            whitelists[_whitelists[index]] = true;
        }
    }

    function removeWhitelist(address[] calldata _whitelists) public onlyOwner {
        for (uint256 index = 0; index < _whitelists.length; index++) {
            delete whitelists[_whitelists[index]];
        }
    }

    function getListInvervestPayment() public view returns(IntervestPayment[] memory){
        uint256 supplys = getTotalSupplyOfId();
        IntervestPayment[] memory _intervestPayment = new IntervestPayment[](supplys);
        for (uint256 index = 0; index < supplys; index++) {
            for (uint256 j = 0; j < intervestPaymentMap[index].length; j++) {
                if(!intervestPaymentMap[index][j].paid){
                    _intervestPayment[index] = intervestPaymentMap[index][j];
                    break;
                }
            }
        }
        return _intervestPayment;
    }

    function getListInvervestPaymentTemp(uint256 id) public view returns(IntervestPayment memory){
        for (uint256 index = 0; index < intervestPaymentMapTemp[id].length; index++) {
            if(!intervestPaymentMapTemp[id][index].paid){
                return intervestPaymentMapTemp[id][index];
            }
        }
        return intervestPaymentMapTemp[id][intervestPaymentMapTemp[id].length - 1];
    }

    function getInvervestPaymentsById(uint256 id) public view returns(IntervestPayment[] memory){
        return intervestPaymentMap[id];
    }

    function getInvervestPaymentsTempById(uint256 id) public view returns(IntervestPayment[] memory){
        return intervestPaymentMapTemp[id];
    }

    function getTotalSupplyOfId() public view returns(uint256){
        return _issueIdCounter.current();
    }

    function setProvider(address _provider) public onlyOwner{
        fundCertProvider = FundCertProvider(_provider);
    }

    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        internal
        whenNotPaused
        override(ERC1155, ERC1155Supply)
    {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }
}