const { expect, assert } = require("chai");
const { upgrades, ethers } = require("hardhat");

describe("Blockchain Monster Settings", function () {
  let bcmSettingsInstance;
  let owner;
  let addr1;
  let addr2;
  let addrs;
  let speciesSetting1;
  let speciesSetting2;

  beforeEach(async function () {
    [owner, addr1, addr2, ...addrs] = await ethers.getSigners();

    const BCMSettings = await ethers.getContractFactory("BCMSettings");
    bcmSettingsInstance = await upgrades.deployProxy(BCMSettings, {
      kind: "uups",
    });
    await bcmSettingsInstance.deployed();
    await bcmSettingsInstance.grantRole(
      bcmSettingsInstance.PARTNER_CONTRACT_ROLE(),
      owner.address
    );

    // preset some blockhash: block 12345 => match with id 40
    await bcmSettingsInstance.setBlockHash(
      12345,
      ethers.BigNumber.from("12415530483918814249")
    );

    // bh_start = 12415530483918814048, bh_end = 12610086098002277759, type = [1, 2]
    // battle_bcmc_staking_requirement = 10BCMC, battle_bcmc_reward = 8BCMC, battle_total_rewarded_winner = 2, battle_insurance_fee = 35$
    // catching_min_power = 20$, catching_limit_per_block = 5, catching_start_success_rate = 60, catching_cost_per_sr_percentage = 1$
    // catching_require_assist_type = 3, catching_require_assist_min_exp = 20, catching_require_assist_max_exp = 1000
    // [80, 70, 60, 50, 40, 30]
    speciesSetting1 = ethers.BigNumber.from(
      "77933547946353024075082418532612499980085293345073630603535821425213515500972"
    );
    speciesSetting2 = ethers.BigNumber.from(
      "53919895487598258933799825820858378146618790772361542910696055235411968"
    );
    await bcmSettingsInstance.setSpeciesSetting(
      40,
      speciesSetting1,
      speciesSetting2
    );
  });

  describe("BCM Settings Deployment Tests", function () {
    it("ensure important functions under access control", async function () {
      await expect(
        bcmSettingsInstance.connect(addr1).pause()
      ).to.be.revertedWith("AccessControl");

      await expect(
        bcmSettingsInstance.connect(addr1).setSpeciesSetting(1, 2, 3)
      ).to.be.revertedWith("AccessControl");

      await expect(
        bcmSettingsInstance.connect(addr1).setBattleSignExpiryTime(300)
      ).to.be.revertedWith("AccessControl");

      await expect(
        bcmSettingsInstance.connect(addr1).setBCMC20Contract(addr2.address)
      ).to.be.revertedWith("AccessControl");

      await expect(
        bcmSettingsInstance.connect(addr1).setChainCurrencyPrice(123)
      ).to.be.revertedWith("AccessControl");

      await expect(
        bcmSettingsInstance
          .connect(addr1)
          .genGene(addr1.address, 0, 0, 0, 1, 0, 0)
      ).to.be.revertedWith("AccessControl");

      await expect(bcmSettingsInstance
        .connect(addr1).setBlockDistribution(0, 0)
      ).to.be.revertedWith("AccessControl");

      await expect(
        bcmSettingsInstance.connect(addr1).setRewardRatioMax(500)
      ).to.be.revertedWith("AccessControl");

      await expect(
        bcmSettingsInstance.connect(addr1).setBlockHash(0, 0)
      ).to.be.revertedWith("AccessControl");
    });
  });

  describe("Settings Config Tests", function () {
    it("species settings work", async function () {
      await bcmSettingsInstance.setSpeciesSetting(1, 2, 3);
      expect(await bcmSettingsInstance.speciesSetting1(1)).to.equal(
        ethers.BigNumber.from(2)
      );
      expect(await bcmSettingsInstance.speciesSetting2(1)).to.equal(
        ethers.BigNumber.from(3)
      );

      expect(await bcmSettingsInstance.getSpeciesSetting(1)).to.eql([
        ethers.BigNumber.from(2),
        ethers.BigNumber.from(3),
      ]);
    });

    it("test setting attribute", async function () {
      await bcmSettingsInstance.setSpeciesSetting(
        1,
        speciesSetting1,
        speciesSetting2
      );
      expect(await bcmSettingsInstance.getFixedSpeciesSetting(1)).to.eql([
        ethers.BigNumber.from("12415530483918814048"),
        ethers.BigNumber.from("12610086098002277759"),
        ethers.BigNumber.from(1),
        ethers.BigNumber.from(2),
      ]);

      await bcmSettingsInstance.setChainCurrencyPrice(451*100);
      expect(await bcmSettingsInstance.getCatchSpeciesSetting(1)).to.eql([
        ethers.BigNumber.from("44345898004434589"),  //ethers.utils.parseEther(`${20/451}`)  -  min cp
        5, // block limit
        60, // start success rate
        ethers.BigNumber.from("2217294900221729"),  //ethers.utils.parseEther(`${1/451}`), // cost per success rate
        3, // assistant type
        20, // min exp
        1000 // max exp
      ]);
      expect(await bcmSettingsInstance.getBattleSpeciesSetting(1)).to.eql([
        ethers.utils.parseEther("10"), // staking
        ethers.utils.parseEther("8"), // reward
        ethers.BigNumber.from("2"),
        ethers.BigNumber.from("77605321507760532"), // ethers.utils.parseEther(`${35/451}`),
      ]);
      expect(await bcmSettingsInstance.getBattleStats(1)).to.eql([
        80, 70, 60, 50, 40, 30,
      ]);
    });

    it("block and species logic", async function () {
      // bh is not a catch
      await bcmSettingsInstance.setBlockHash(
        11111,
        ethers.BigNumber.from("12415530483918814047")
      );
      await expect(
        bcmSettingsInstance.genGene(addr1.address, 0, 11111, 0, 40, 0, 0)
      ).to.be.revertedWith("not_catch_block");

      // bh is invalid
      await bcmSettingsInstance.setBlockHash(
        11111,
        ethers.BigNumber.from("12415530483918814007")
      );
      await expect(
        bcmSettingsInstance.genGene(addr1.address, 0, 11111, 0, 40, 0, 0)
      ).to.be.revertedWith("invalid_species");

      // no setting
      await expect(
        bcmSettingsInstance.genGene(addr1.address, 0, 101010101010, 0, 10, 0, 0)
      ).to.be.revertedWith("invalid_block");
    });

    it("test gen gene for invalid catching power", async function () {
      await expect(
        bcmSettingsInstance.genGene(
          addr1.address,
          0,
          12345,
          0, // min catch
          40,
          0,
          0
        )
      ).to.be.revertedWith("invalid_cp");
    });

    it("ensure no exceed monster limit", async function () {
      await bcmSettingsInstance.setChainCurrencyPrice(451*100);
      await expect(
        bcmSettingsInstance.genGene(
          addr1.address,
          ethers.utils.parseEther("0.0444"),
          12345,
          5,
          40,
          0,
          0
        )
      ).to.be.revertedWith("limit_reach");
    });
  });
});
