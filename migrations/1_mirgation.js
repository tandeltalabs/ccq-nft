const FundCertMarketplaceContract = artifacts.require("FundCertMarketplace");
const ETFContract = artifacts.require("FundGoETFWrapped");
const BUSDContract = artifacts.require("BUSD");
const ISSUE_DATE = 1682418934;
const PRICE = 100000;

module.exports = async function(deployer, network, accounts) {
    deployer.deploy(BUSDContract, "VNDC", "VNDC", 0, 200000000000, {from: accounts[0]}).then(function() {
        return deployer.deploy(FundCertMarketplaceContract, BUSDContract.address, true, {from: accounts[0]}).then(function(){
            return deployer.deploy(
                ETFContract, accounts[1], 
                "deltalabs", 
                ISSUE_DATE, 
                10000, 
                92,
                2,
                80, 
                PRICE, 
                BUSDContract.address, 
                FundCertMarketplaceContract.address, 
                {from: accounts[0]}
            );
        })
    });
    
}
