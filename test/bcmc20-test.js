const { expect } = require("chai");
const { upgrades, ethers } = require("hardhat");

describe("Blockchain Monster Coin ERC20", function () {
  let bcmcInstance;
  let owner;
  let addr1;
  let addr2;
  let addrs;

  beforeEach(async function () {
    [owner, addr1, addr2, ...addrs] = await ethers.getSigners();

    const BCMERC721 = await ethers.getContractFactory("BlockchainMonster");
    const bcm721Instance = await upgrades.deployProxy(BCMERC721, {
      kind: "uups",
    });

    const BCMCERC20 = await ethers.getContractFactory("BlockchainMonsterCoin");
    bcmcInstance = await upgrades.deployProxy(BCMCERC20, {
      kind: "uups",
    });
    await bcmcInstance.deployed();
    await bcmcInstance.initMint(owner.address, ethers.utils.parseEther("250000000.0"));
    await bcmcInstance.setBCMERC721Contract(bcm721Instance.address);
  });

  describe("ERC20 Deployment Tests", function () {
    it("ensure success deploy", async function () {
      // test basic
      expect(await bcmcInstance.name()).to.equal("Blockchain Monster Coin");
      expect(await bcmcInstance.symbol()).to.equal("BCMC");
      expect(await bcmcInstance.decimals()).to.equal(18);
      expect(await bcmcInstance.balanceOf(owner.address)).to.equal(
        ethers.BigNumber.from(10).pow(18).mul(250000000)
      );
    });

    it("upgrade is success", async function () {
      // test basic
      const BCMCTest = await ethers.getContractFactory(
        "BlockchainMonsterCoinTest"
      );
      const bcmcTestInstance = await upgrades.upgradeProxy(
        bcmcInstance,
        BCMCTest
      );
      expect(await bcmcTestInstance.name()).to.equal("test");
      await bcmcTestInstance.setVersion("v2");
      expect(await bcmcTestInstance.version()).to.equal("v2");

      expect(await bcmcTestInstance.balanceOf(owner.address)).to.equal(
        ethers.BigNumber.from(10).pow(18).mul(250000000)
      );
    });

    it("access control works well", async function () {
      // test role
      await expect(bcmcInstance.connect(addr1).pause()).to.be.reverted;
      // give role to multiple people
      await bcmcInstance.grantRole(bcmcInstance.PAUSER_ROLE(), addr1.address);
      expect(
        await bcmcInstance.hasRole(bcmcInstance.PAUSER_ROLE(), addr1.address)
      ).to.equal(true);

      // try remove pause for the admin
      await bcmcInstance.revokeRole(bcmcInstance.PAUSER_ROLE(), owner.address);
      expect(
        await bcmcInstance.hasRole(bcmcInstance.PAUSER_ROLE(), owner.address)
      ).to.equal(false);

      // revoke role
      await expect(
        bcmcInstance
          .connect(addr1)
          .revokeRole(bcmcInstance.DEFAULT_ADMIN_ROLE(), owner.address)
      ).to.be.revertedWith("AccessControl");
      await bcmcInstance.grantRole(
        bcmcInstance.DEFAULT_ADMIN_ROLE(),
        addr1.address
      );
      await bcmcInstance
        .connect(addr1)
        .revokeRole(bcmcInstance.DEFAULT_ADMIN_ROLE(), owner.address);
      await expect(
        bcmcInstance.grantRole(bcmcInstance.PAUSER_ROLE(), addr2.address)
      ).to.be.reverted;
    });

    it("ensure no exceed limit", async function () {
      await expect(
        bcmcInstance.initMint(owner.address, ethers.utils.parseEther("1250000000.0"))
      ).to.be.revertedWith("exceed_max_supply");
    });

    it("ensure important functions under access control", async function () {
      await expect(
        bcmcInstance.connect(addr1).setBCMERC721Contract(addr2.address)
      ).to.be.revertedWith("AccessControl");
      await expect(
        bcmcInstance.connect(addr1).setExchangeRate(123)
      ).to.be.revertedWith("AccessControl");
      await expect(
        bcmcInstance.connect(addr1).setBCMPortalContracts(addr2.address, owner.address)
      ).to.be.revertedWith("AccessControl");
      await expect(
        bcmcInstance.connect(addr1).initMint(owner.address, ethers.utils.parseEther("250000000.0"))
      ).to.be.revertedWith("AccessControl");
    });

    it("ensure enough BCMC to catch monster", async function () {
/*
      await expect(
        bcmcInstance
          .connect(addr1)
          .catchMonsterByBCMC(ethers.BigNumber.from(10).pow(18), 1, 1, 1)
      ).to.be.revertedWith("low_balance");

      await expect(
        bcmcInstance
          .connect(addr1)
          .battleMonsterByBCMC(
            ethers.BigNumber.from(10).pow(18),
            1,
            1,
            1,
            1,
            "0x00"
          )
      ).to.be.revertedWith("low_balance");
  */
    });
  });
});
