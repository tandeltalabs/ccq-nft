const web3 = require('web3');
const FundCert = artifacts.require("FundCertificate");
const FundCertProvider = artifacts.require("FundCertProvider");

function getEtherFromWie(wei){
    return web3.utils.fromWei(wei);
}

contract("FundCert", (accounts) => {
    const OWNER = accounts[0];
    const PUBLISHER_1 = accounts[1];
    const PUBLISHER_2 = accounts[2];
    const PUBLISHER_3 = accounts[3];
    const ISSUE_DATE = 1680681300 // 8:00 pm;
    const INTERVEST_TERM = 92;
    const PRICE = '10000000000000000000000';
    const ADDRESS_0 = '0x0000000000000000000000000000000000000000';

    // it("create sample contract wrrap", async () => {
      
    //     const fundCertProvider = await FundCertProvider.deployed();
    //     await fundCertProvider.createContract(100, ADDRESS_0, PUBLISHER_1, 100);
    //     await fundCertProvider.createContract(101, ADDRESS_0, PUBLISHER_2, 100);
    //     await fundCertProvider.createContract(102, ADDRESS_0, PUBLISHER_3, 100);
    //     const getContract = await fundCertProvider.getContractAddress(100);
    //     const getContract2 = await fundCertProvider.getContractAddress(101);
    //     const getContract3 = await fundCertProvider.getContractAddress(102);

    //     console.log(getContract);
    //     console.log(getContract2);
    //     console.log(getContract3);
    // });

    it("phat hanh 200000 cqq", async () => {
        const FundCertContract = await FundCert.deployed();
        const fundCertProvider = await FundCertProvider.deployed();
        await fundCertProvider.setCreater(FundCertContract.address);
        await FundCertContract.issue(PUBLISHER_1, ISSUE_DATE, 20, INTERVEST_TERM, PRICE);

        const getContract = await fundCertProvider.getContractAddress(0);
        const balance = await FundCertContract.balanceOf(OWNER, 0);
        const balancev2 = await fundCertProvider.fundCertificateWrapped.balanceOf(PUBLISHER_1, 0);

        console.log(getContract);
        console.log(balance.toNumber());
        console.log(balancev2.toNumber());
    });

});
