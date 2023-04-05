const FundCertContract = artifacts.require("FundCertificate");
const FundCertProviderContract = artifacts.require("FundCertProvider");
const BUSDContract = artifacts.require("BUSD");

module.exports = async function(deployer, network, accounts) {
    deployer.deploy(BUSDContract, {from: accounts[0]}).then(function() {
        return deployer.deploy(FundCertProviderContract, {from: accounts[0]}).then(function(){
            return deployer.deploy(FundCertContract, BUSDContract.address, FundCertProviderContract.address, {from: accounts[0]});
        })
    });
    deployer.deploy(BUSDContract, {from: accounts[0]});
}