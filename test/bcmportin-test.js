const { expect } = require("chai");
const { upgrades, ethers } = require("hardhat");

describe("BCM Portal In", function () {
  let bcmcInstance;
  let bcmcPortalInstance;
  let owner;
  let addr1;
  let addr2;
  let addrs;

  /*
  beforeEach(async function () {
    [owner, addr1, addr2, ...addrs] = await ethers.getSigners();

    const BCMCERC20 = await ethers.getContractFactory("BlockchainMonsterCoin");
    bcmcInstance = await upgrades.deployProxy(BCMCERC20, {
      kind: "uups",
    });
    await bcmcInstance.deployed();

    const BCMPortalIn = await ethers.getContractFactory("BCMPortalInTest");
    bcmcPortalInstance = await upgrades.deployProxy(BCMPortalIn, {
      kind: "uups",
    });
    await bcmcPortalInstance.deployed();
  });

  describe("BCMC Portal Deployment Tests", function () {
    it("access control works well", async function () {
      // test role
      await expect(bcmcPortalInstance.connect(addr1).pause()).to.be.reverted;
      // give role to multiple people
      await bcmcPortalInstance.grantRole(bcmcInstance.PAUSER_ROLE(), addr1.address);
      expect(
        await bcmcPortalInstance.hasRole(bcmcInstance.PAUSER_ROLE(), addr1.address)
      ).to.equal(true);
    });

    it("ensure important functions under access control", async function () {
      await expect(
        bcmcPortalInstance.connect(addr1).setTransportSettings(1, addr2.address, addr2.address, addr2.address, 0)
      ).to.be.revertedWith("AccessControl");
      await expect(
        bcmcPortalInstance.connect(addr1).setPortalSettings(1, 1, addr2.address)
      ).to.be.revertedWith("AccessControl");
      await expect(
        bcmcPortalInstance.connect(addr1).setBCMCERC20Contract(addr2.address)
      ).to.be.revertedWith("AccessControl");

      await expect(
        bcmcPortalInstance.connect(addr1).withdrawBCMCToken(addr1.address, ethers.utils.parseEther("1.0"))
      ).to.be.revertedWith("AccessControl");
      await expect(
        bcmcPortalInstance.connect(addr1).withdrawTransportToken(1, addr1.address, ethers.utils.parseEther("1.0"))
      ).to.be.revertedWith("AccessControl");
      await expect(
        bcmcPortalInstance.connect(addr1).withdrawPToken(1, addr1.address, ethers.utils.parseEther("1.0"))
      ).to.be.revertedWith("AccessControl");
    });
  })
*/
});
