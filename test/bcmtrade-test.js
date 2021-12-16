const { expect, assert } = require("chai");
const { upgrades, ethers } = require("hardhat");

describe("BCM Marketplace", function () {
  let bcmTradeInstance;
  let bcm721Test;
  let bcmc20Instance;
  let owner;
  let addr1;

  beforeEach(async function () {
    [owner, addr1, addr2, ...addrs] = await ethers.getSigners();

    const BCMTrade = await ethers.getContractFactory("BCMTrade");
    bcmTradeInstance = await upgrades.deployProxy(BCMTrade, {
      kind: "uups",
    });
    await bcmTradeInstance.deployed();

    // deploy bcm
    const BCMERC721 = await ethers.getContractFactory("BlockchainMonster");
    const bcm721Instance = await upgrades.deployProxy(BCMERC721, {
      kind: "uups",
    });
    const BlockchainMonsterTest = await ethers.getContractFactory(
      "BlockchainMonsterTest"
    );
    bcm721Test = await upgrades.upgradeProxy(
      bcm721Instance,
      BlockchainMonsterTest
    );
    await bcm721Test.deployed();
    // grant access for bcm trade
    await bcm721Test.grantRole(
      bcm721Test.PARTNER_CONTRACT_ROLE(),
      bcmTradeInstance.address
    );

    // deploy erc20
    const BCMCERC20 = await ethers.getContractFactory("BlockchainMonsterCoin");
    bcmc20Instance = await upgrades.deployProxy(BCMCERC20, {
      kind: "uups",
    });
    await bcmc20Instance.deployed();
    await bcmc20Instance.initMint(owner.address, ethers.utils.parseEther("250000000.0"));
    await bcmc20Instance.setBCMERC721Contract(bcm721Instance.address);
    await bcmc20Instance.setBCMTradeContract(bcmTradeInstance.address);

    // add dependence contract
    await bcmTradeInstance.setDepContracts(bcm721Instance.address, bcmc20Instance.address);
    
  })

  describe("BCM Marketplace Deployment Tests", function () {
    it("ensure important functions under access control", async function () {
      await expect(
        bcmTradeInstance.connect(addr1).setDepContracts(addr1.address, addr2.address)
      ).to.be.revertedWith("AccessControl");
      await expect(
        bcmTradeInstance.connect(addr1).setFeeRate(2, 3)
      ).to.be.revertedWith("AccessControl");
      await expect(
        bcmTradeInstance.connect(addr1).withdraw(addr1.address, ethers.utils.parseEther("1.0"))
      ).to.be.revertedWith("AccessControl");
      await expect(
        bcmTradeInstance.connect(addr1).withdrawToken(addr1.address, ethers.utils.parseEther("1.0"))
      ).to.be.revertedWith("AccessControl");
      await expect(
        bcmTradeInstance.connect(addr1).executeTradeUsingBCMC(owner.address, 1, addr1.address, 100, 1, ethers.utils.parseEther("1.0"), 
        0, "0x00")
      ).to.be.reverted;
    });

    it("ensure withdraw function work", async function () {
      await expect(await owner.sendTransaction({to: bcmTradeInstance.address, value: ethers.utils.parseEther("1.0")})
      ).to.changeEtherBalance(owner, ethers.utils.parseEther("-1.0"));
      await expect(await bcmTradeInstance.withdraw(addr1.address, ethers.utils.parseEther("0.5"))
      ).to.changeEtherBalance(addr1, ethers.utils.parseEther("0.5"));;
    });

    it("ensure withdraw bcmc work", async function () {
      await bcmc20Instance.transfer(bcmTradeInstance.address, ethers.utils.parseEther("1.0"));
      await bcmTradeInstance.withdrawToken(addr1.address, ethers.utils.parseEther("0.5"));
      expect(await bcmc20Instance.balanceOf(addr1.address)).to.equal(ethers.utils.parseEther("0.5"));
    });

  });

  /*
  describe("Execute Trade Tests", function () {
    it("invalid amount is blocked", async function () {
      await expect(bcmTradeInstance.executeTrade(1, addr2.address, 100, 1, ethers.utils.parseEther("1.0"), 0,
       "0x85a711fa0015a056bca4dd88b7f36a6a3da68e5793f688f68b3ca71923af04975b17f7bbffab3bf95b50d9a23b118f0f78c7254cf5cada6517d50e608cebc8ee1c")
      ).to.be.revertedWith("invalid_amount");
      await expect(bcmTradeInstance.executeTrade(1, addr2.address, 100, 1, ethers.utils.parseEther("1.0"), 0,
       "0x85a711fa0015a056bca4dd88b7f36a6a3da68e5793f688f68b3ca71923af04975b17f7bbffab3bf95b50d9a23b118f0f78c7254cf5cada6517d50e608cebc8ee1c",
       {value: ethers.utils.parseEther("0.5")})).to.be.revertedWith("invalid_amount");
    });
    it("block when the signer is not the token owner", async function () {
      // no token
      await expect(bcmTradeInstance.executeTrade(1, addr2.address, 100, 1, ethers.utils.parseEther("1.0"), 0,
       "0x10305747a89252826de1c4817a63e98b237377202e073cd8f75a8c269774fddd1961c00519894e3693b24c4d31c0c8fef530a1b15791bd5cb19fa359da36d82d1c",
       {value: ethers.utils.parseEther("1.0")})
      ).to.be.revertedWith("ERC721: owner query for nonexistent token");

      // kind: 0, hash: 0, species:1, pri_type: 3, second_type: 4, [90, 80, 70, 60, 50, 40], 0
      await bcm721Test.setMonster(
        addr1.address,
        100,
        ethers.BigNumber.from("5776272187679102680360502204526423446575382528")
      );
      await expect(bcmTradeInstance.executeTrade(1, addr2.address, 100, 1, ethers.utils.parseEther("1.0"), 0,
       "0x10305747a89252826de1c4817a63e98b237377202e073cd8f75a8c269774fddd1961c00519894e3693b24c4d31c0c8fef530a1b15791bd5cb19fa359da36d82d1c",
       {value: ethers.utils.parseEther("1.0")})
      ).to.be.revertedWith("invalid_owner");

      // correct owner but not match monster id in signature
      await bcm721Test.setMonster(
        addr2.address,
        2,
        ethers.BigNumber.from("5776272187679102680360502204526423446575382528")
      );
      await expect(bcmTradeInstance.executeTrade(1, addr2.address, 2, 1, ethers.utils.parseEther("1.0"), 0,
       "0x10305747a89252826de1c4817a63e98b237377202e073cd8f75a8c269774fddd1961c00519894e3693b24c4d31c0c8fef530a1b15791bd5cb19fa359da36d82d1c",
       {value: ethers.utils.parseEther("1.0")})
      ).to.be.revertedWith("invalid_signature");

    });

    it("success execute trade", async function () {
      // signagure is hardcoded by this address
      expect(bcm721Test.address).to.equal("0xf1c99B18CeFa77549C37ffC3C3AB8a356CAaC623");
      expect(bcmTradeInstance.address).to.equal("0x0335DCC52C3cfdE6AeAef90357D6065e4d60Ccf8");
      // kind: 0, hash: 0, species:1, pri_type: 3, second_type: 4, [90, 80, 70, 60, 50, 40], 0
      await bcm721Test.setMonster(
        addr2.address,
        100,
        ethers.BigNumber.from("5776272187679102680360502204526423446575382528")
      );
      await expect(await bcmTradeInstance.executeTrade(1, addr2.address, 100, 1, ethers.utils.parseEther("1.0"), 0,
       "0x1be223f82d08e97755e169584c073aaecddf849fc604a26f8878c0698d0cf7ac08ebaa5e4dd6e85ff03b71991d3f386e38b23504645326204276783ae0f6e5e71b",
       {value: ethers.utils.parseEther("1.0")})
      ).to.changeEtherBalance(bcmTradeInstance, ethers.utils.parseEther("1.0").mul(await bcmTradeInstance.feeRateChainCoin()).div(100));
      expect(await bcm721Test.ownerOf(100)).to.equal(owner.address);
    });

    it("ensure block trade when the deadline is over", async function () {
      // signagure is hardcoded by this address
      expect(bcm721Test.address).to.equal("0x4Bf872A4ac5ebEa0BABe8B5e3718e2731923B59b");
      expect(bcmTradeInstance.address).to.equal("0xD82E2F3fEe8B277ceF3A8f16C6eB8f654E77ee03");
      // kind: 0, hash: 0, species:1, pri_type: 3, second_type: 4, [90, 80, 70, 60, 50, 40], 0
      await bcm721Test.setMonster(
        addr2.address,
        100,
        ethers.BigNumber.from("5776272187679102680360502204526423446575382528")
      );
      await expect(bcmTradeInstance.executeTrade(1, addr2.address, 100, 1, ethers.utils.parseEther("1.0"), 1,
       "0xe78d560a4296dc462d34163a595ac4aebb19600ef7309e6a509a3ca4cc62e64a475422d4a55f59c024be218938dad6959194b2e75e628ad7c1a0856397bf23821c",
       {value: ethers.utils.parseEther("1.0")})
      ).to.be.revertedWith("expired_deadline");
    });

    it("cancel trade", async function () {
      // signagure is hardcoded by this address
      expect(bcm721Test.address).to.equal("0x311baa8a3FeBA4595d4f9186e4f3f0087ed34A13");
      expect(bcmTradeInstance.address).to.equal("0xf369C14e21f5A21cFffef44D22344fB46497FD7C");
      // call cancel
      await expect(bcm721Test.cancelPermitTrade(1))
      .to.emit(bcm721Test, "CancelPermitTradeEvt")
      .withArgs(addr2.address, 1);

      // kind: 0, hash: 0, species:1, pri_type: 3, second_type: 4, [90, 80, 70, 60, 50, 40], 0
      await bcm721Test.setMonster(
        addr2.address,
        100,
        ethers.BigNumber.from("5776272187679102680360502204526423446575382528")
      );
      await expect(bcmTradeInstance.executeTrade(1, addr2.address, 100, 1, ethers.utils.parseEther("1.0"), 0,
       "0x4d7cde0fa4ca573d02a550e59f6ab74c10833c5e1023949f8d13b2450f470c736fc71fbb2042316b438427eb434fc84365df5826e65fc89f514e4092fa06f91e1b",
       {value: ethers.utils.parseEther("1.0")})
      ).to.be.revertedWith("used_permit");
    });
  });

  describe("BCMC Execute Trade Tests", function () {
    it("invalid amount", async function () {
      await expect(bcmc20Instance.connect(addr1).executeTradeByBCMC(1, addr2.address, 100, 2, ethers.utils.parseEther("1.0"), 0, 
      "0x85a711fa0015a056bca4dd88b7f36a6a3da68e5793f688f68b3ca71923af04975b17f7bbffab3bf95b50d9a23b118f0f78c7254cf5cada6517d50e608cebc8ee1c")
      ).to.be.revertedWith("low_balance");
    });

    it("invalid currency", async function () {
      await expect(bcmc20Instance.executeTradeByBCMC(1, addr2.address, 100, 1, ethers.utils.parseEther("1.0"), 0, 
      "0x85a711fa0015a056bca4dd88b7f36a6a3da68e5793f688f68b3ca71923af04975b17f7bbffab3bf95b50d9a23b118f0f78c7254cf5cada6517d50e608cebc8ee1c")
      ).to.be.revertedWith("invalid_currency");
    });

    
    it("success pay with bcmc", async function () {
      expect(bcm721Test.address).to.equal("0xF69C0fbd324aDfcC52aB87A66361f97f0B5f8c3A");
      expect(bcmTradeInstance.address).to.equal("0x4576c9b64f7c869bA3f591B97E912f342f654C37");
      // kind: 0, hash: 0, species:1, pri_type: 3, second_type: 4, [90, 80, 70, 60, 50, 40], 0
      await bcm721Test.setMonster(
        addr2.address,
        100,
        ethers.BigNumber.from("5776272187679102680360502204526423446575382528")
      );
      await expect(bcmc20Instance.executeTradeByBCMC(1, addr2.address, 100, 2, ethers.utils.parseEther("1.0"), 0, 
      "0x338aa01f277a32511eb882a0a1b565e564da8f315197d6bda236c6978c1349eb0182f22e4a931732f26485b81d98ec67407efdf5f8d67538dfa332320168a1161c")
      ).to.emit(bcm721Test, "Transfer")
      .withArgs(addr2.address, owner.address, 100);
      expect(await bcmc20Instance.balanceOf(addr2.address)).to.equal(ethers.utils.parseEther("1.0").mul(100 - (await bcmTradeInstance.feeRateBCMC())).div(100));
    });  
     
  });
*/
})
