const FundCertMarketplaceContract = artifacts.require("FundCertMarketplace");
const ETFContract = artifacts.require("FundGoETFWrapped");
const BUSDContract = artifacts.require("BUSD");
const ISSUE_DATE = 1681873230;
const PRICE =   '10000000000000000000';

module.exports = async function(deployer, network, accounts) {
    deployer.deploy(BUSDContract, {from: accounts[0]}).then(function() {
        return deployer.deploy(FundCertMarketplaceContract, BUSDContract.address, true, {from: accounts[0]}).then(function(){
            return deployer.deploy(ETFContract, accounts[1], "deltalabs", ISSUE_DATE, 10000, 30, PRICE, BUSDContract.address, FundCertMarketplaceContract.address, {from: accounts[0]});
        })
    });
    
}