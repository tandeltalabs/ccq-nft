// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./fund-cert-nft-wrap.sol";

contract FundCertProvider is Ownable {
    mapping(uint256 => address) contractWrap;
    address creater;

    modifier onlyCreater(address _creater) {
        require(creater == _creater, "this feature just for creater");
        _;
    }

    function createContract(
        address _owner,
        uint256 _tokenId, 
        address _contractFC, 
        address _publisher, 
        uint256 _amount) 
        public 
        onlyCreater(msg.sender)
    {
        FundCertificateWrapped fundCertificateWrapped = new FundCertificateWrapped(_tokenId, _contractFC, _publisher, _amount);
        fundCertificateWrapped.transferOwnership(_owner);
        contractWrap[_tokenId] = address(fundCertificateWrapped);
    }

    function getContractAddress(uint256 _tokenId) public view returns(address){
        return contractWrap[_tokenId];
    } 

    function setCreater(address _newCreater) public onlyOwner{
        creater = _newCreater;
    }

    function getCreater() public view returns(address){
        return creater;
    }
}