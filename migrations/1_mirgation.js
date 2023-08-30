const FundCertMarketplaceContract = artifacts.require("FundCertMarketplace");
const ETFContract = artifacts.require("FundGoETFWrapped");
const BUSDContract = artifacts.require("BUSD");

module.exports = async function(deployer, network, accounts) {
    deployer.then(async () => {
        await deployer.deployer();

    })
    
}
