const web3 = require('web3');
const FundCertWrap = artifacts.require("FundGoETFWrapped");
const FCMarketplace = artifacts.require("FundCertMarketplace");
const BUSD = artifacts.require("BUSD");

function getEtherFromWie(wei){
    return web3.utils.fromWei(wei);
}

contract("FundCert", (accounts) => {
    const OWNER = accounts[0];
    const PUBLISHER_1 = accounts[1];
    const BALANCE = '1000000000000000000000000';
    const ADDRESS_0 = '0x0000000000000000000000000000000000000000';
    const testBuyP2P = '100000000000000000000';
    const BUYER = accounts[2];
    const BUYER_1 = accounts[3];
    // issuer test
    it("pay intervest", async () => {
      
    });

    // publisher test
    it("list NFT to market", async () => {
        const BUSDContract = await BUSD.deployed();
        const FCMarketplaceContract = await FCMarketplace.deployed();
        const FundCertWrapContract = await FundCertWrap.deployed();
        // add publisher to market place 
        await FCMarketplaceContract.addPublisher(PUBLISHER_1);
        // approve for market get NFT from publisher
        await FundCertWrapContract.setApprovalForAll(FCMarketplaceContract.address, true, {from: PUBLISHER_1});
        // sell item to market
        await FCMarketplaceContract.sellItem(FundCertWrapContract.address, 0, 3000, {from: PUBLISHER_1});
        await FCMarketplaceContract.sellItem(FundCertWrapContract.address, 0, 3000, {from: PUBLISHER_1});
        await FCMarketplaceContract.sellItem(FundCertWrapContract.address, 0, 3000, {from: PUBLISHER_1});
        await BUSDContract.mint(BUYER, BALANCE);
        await BUSDContract.approve(FCMarketplaceContract.address, BALANCE, { from: BUYER});

        await FCMarketplaceContract.buyItem([[0, 1000],[1, 1000], [2, 1000]], {from: BUYER});
        await FundCertWrapContract.sellNow(5, 1000, {from: BUYER});
        const myAsset = await FundCertWrapContract.getMyAsset(BUYER);
        console.log(myAsset);
        // await FundCertWrapContract.sellNow()
       
       
        // const vestList = await FundCertWrapContract.getMyVestList(FCMarketplaceContract.address, 1);
        // console.log(vestList);
      
       

       

    });

    it("delist NFT on market", async () => {
        // const FCMarketplaceContract = await FCMarketplace.deployed();
        // const FundCertWrapContract = await FundCertWrap.deployed();
        // // add publisher to market place 
        // await FCMarketplaceContract.addPublisher(PUBLISHER_1);
        // // approve for market get NFT from publisher
        // await FundCertWrapContract.setApprovalForAll(FCMarketplaceContract.address, true, {from: PUBLISHER_1});
        // // sell item to market
        // await FCMarketplaceContract.sellItem(FundCertWrapContract.address, 0, 1000, {from: PUBLISHER_1});

        // const balance1 = await FundCertWrapContract.balanceOf(PUBLISHER_1, 0);
        // const balance2 = await FundCertWrapContract.balanceOf(FCMarketplaceContract.address, 1);
        // assert.equal(
        //     balance1.toNumber(),
        //     9000,
        //     "balance wrong value"
        // );

        // assert.equal(
        //     balance2.toNumber(),
        //     1000,
        //     "balance wrong value"
        // );

    });

    it("pay intervest temp", async () => {
      
    }); 

    it("take profit", async () => {
      
    });   
    
    
    // user test
    it("Buy 1 CQQ in market", async () => {
        // const BUSDContract = await BUSD.deployed();
        // const FCMarketplaceContract = await FCMarketplace.deployed();
        // const FundCertWrapContract = await FundCertWrap.deployed();

        // await BUSDContract.mint(BUYER, BALANCE);
        // await BUSDContract.approve(FCMarketplaceContract.address, BALANCE, { from: BUYER});

        // await FCMarketplaceContract.buyItem([[0, 1000]], {from: BUYER});
        // const balance1 = await FundCertWrapContract.balanceOf(BUYER, 2);
        // const vestList = await FundCertWrapContract.getMyVestList(BUYER, 2);
        
        // assert.equal(
        //     balance1.toNumber(),
        //     1000,
        //     "balance wrong value"
        // );
    });

    // it("listP2P", async () => {
    //     const FundCertWrapContract = await FundCertWrap.deployed();
    //     await FundCertWrapContract.listP2P(BUYER_1, 2, 10, testBuyP2P, {from: BUYER});

    // });

    // it("BuyP2p", async () => {
    //     const BUSDContract = await BUSD.deployed();
    //     const FundCertWrapContract = await FundCertWrap.deployed();
    //     await BUSDContract.mint(BUYER_1, BALANCE);
    //     await BUSDContract.approve(FundCertWrapContract.address, BALANCE, { from: BUYER_1});
    //     await FundCertWrapContract.buyP2P(1, {from: BUYER_1});
    // });


    // it("sell now", async () => {
    //     const FundCertWrapContract = await FundCertWrap.deployed();
    //     // const logRs = await FundCertWrapContract.testLog();
    //     // console.log("LOG:",logRs.toNumber());
    //     await FundCertWrapContract.sellNow(2, 1000, {from: BUYER});
    // });

    it("sell with deal", async () => {
      
    });

    it("hardvest", async () => {
      
    });

    it("redeem", async () => {
      
    });
});
