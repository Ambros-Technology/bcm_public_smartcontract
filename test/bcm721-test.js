const { expect } = require("chai");
const { upgrades, ethers } = require("hardhat");

describe("Blockchain Monster ERC721", function () {
  let bcm721Test;
  let bcmSettingsTest;
  let bcmc20Instance;
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
    // upgrade to test
    const BlockchainMonsterTest = await ethers.getContractFactory(
      "BlockchainMonsterTest"
    );
    bcm721Test = await upgrades.upgradeProxy(
      bcm721Instance,
      BlockchainMonsterTest
    );
    await bcm721Test.deployed();

    // deploy bcmsettings
    const BCMSettings = await ethers.getContractFactory("BCMSettings");
    const bcmSettingsInstance = await upgrades.deployProxy(BCMSettings, {
      kind: "uups",
    });
    // upgrade setting to test
    const BCMSettingsTest = await ethers.getContractFactory("BCMSettingsTest");
    bcmSettingsTest = await upgrades.upgradeProxy(
      bcmSettingsInstance,
      BCMSettingsTest
    );
    await bcmSettingsTest.deployed();
    // set chain currency price
    await bcmSettingsTest.setChainCurrencyPrice(451*100);
    // set sample blockhash
    // this block mapping to species 40
    await bcmSettingsTest.setBlockHash(
      12345,
      ethers.BigNumber.from("12415530483918814249")
    );

    // bh_start = 12415530483918814048, bh_end = 12610086098002277759, type = [1, 2]
    // battle_bcmc_staking_requirement = 10BCMC, battle_bcmc_reward = 8BCMC, battle_total_rewarded_winner = 2, battle_insurance_fee = 35$
    // catching_min_power = 20$, catching_limit_per_block = 5, catching_start_success_rate = 60, catching_cost_per_sr_percentage = 1$
    // catching_require_assist_type = 3, catching_require_assist_min_exp = 20, catching_require_assist_max_exp = 1000
    // [80, 70, 60, 50, 40, 30]
    await bcmSettingsTest.setSpeciesSetting(
      40,
      ethers.BigNumber.from(
        "77933547946353024075082418532612499980085293345073630603535821425213515500972"
      ),
      ethers.BigNumber.from(
        "53919895487598258933799825820858378146618790772361542910696055235411968"
      )
    );
    // bh_start = 1, bh_end = ...
    // battle_bcmc_staking_requirement = 0, battle_bcmc_reward = 8, battle_total_rewarded_winner = 2, battle_insurance_fee = 35$
    // catching_min_power = 0$, catching_limit_per_block = 5, catching_start_success_rate = 60, catching_cost_per_sr_percentage = 1$
    // catching_require_assist_type = 0, catching_require_assist_min_exp = 0, catching_require_assist_max_exp = 0
    // [80, 70, 60, 50, 40, 30]
    await bcmSettingsTest.setSpeciesSetting(
      1,
      ethers.BigNumber.from(
        "156927632256184179823750493913302654135904100792322231724"
      ),
      ethers.BigNumber.from(
        "2153296979344461411141900318443172243940998717269687687624785920"
      )
    );

    // deploy erc20
    const BCMCERC20 = await ethers.getContractFactory("BlockchainMonsterCoin");
    bcmc20Instance = await upgrades.deployProxy(BCMCERC20, {
      kind: "uups",
    });
    await bcmc20Instance.deployed();
    await bcmc20Instance.initMint(owner.address, ethers.utils.parseEther("250000000.0"));
    await bcmc20Instance.setBCMERC721Contract(bcm721Instance.address);

    // set it on erc721
    await bcm721Instance.setDepContracts(
      bcmSettingsTest.address,
      bcmc20Instance.address
    );
    // set internal chain id
    await bcm721Instance.setInternalChainId(12);
    // set erc20 for setting
    await bcmSettingsTest.setBCMC20Contract(bcmc20Instance.address);

    // grant access on setting for erc721
    await bcmSettingsInstance.grantRole(
      bcmSettingsInstance.PARTNER_CONTRACT_ROLE(),
      bcm721Instance.address
    );
  });

  describe("ERC721 Deployment Tests", function () {
    it("ensure success deploy", async function () {
      // test basic
      expect(await bcm721Test.name()).to.equal("Blockchain Monster");
      expect(await bcm721Test.symbol()).to.equal("BCM");
    });

    it("ensure important functions under access control", async function () {
      await expect(
        bcm721Test.connect(addr1).setDepContracts(addr1.address, addr2.address)
      ).to.be.revertedWith("AccessControl");
      await expect(
        bcm721Test.connect(addr1).setInternalChainId(1)
      ).to.be.revertedWith("AccessControl");
      await expect(
        bcm721Test.connect(addr1).withdraw(addr1.address, ethers.utils.parseEther("1.0"))
      ).to.be.revertedWith("AccessControl");
      await expect(
        bcm721Test.connect(addr1).withdrawToken(addr1.address, ethers.utils.parseEther("1.0"))
      ).to.be.revertedWith("AccessControl");
      await expect(
        bcm721Test.catchMonsterByBCMC(addr1.address, 0, 12345, 1, 0)
      ).to.be.reverted;
    });

    it("ensure withdraw function work", async function () {
      await expect(await owner.sendTransaction({to: bcm721Test.address, value: ethers.utils.parseEther("1.0")})
      ).to.changeEtherBalance(owner, ethers.utils.parseEther("-1.0"));
      await expect(await bcm721Test.withdraw(addr1.address, ethers.utils.parseEther("0.5"))
      ).to.changeEtherBalance(addr1, ethers.utils.parseEther("0.5"));;
    });

    it("ensure withdraw bcmc work", async function () {
      await bcmc20Instance.transfer(bcm721Test.address, ethers.utils.parseEther("1.0"));
      await bcm721Test.withdrawToken(addr1.address, ethers.utils.parseEther("0.5"));
      expect(await bcmc20Instance.balanceOf(addr1.address)).to.equal(ethers.utils.parseEther("0.5"));
    });
  });

  describe("BCM Catch Tests", function () {
    beforeEach(async function () {
      // kind: 0, hash: 0, species:1, pri_type: 3, second_type: 4, [90, 80, 70, 60, 50, 40], 0
      await bcm721Test.setMonster(
        addr1.address,
        100,
        ethers.BigNumber.from("5776272187679102680360502204526423446575382528")
      );
      await bcm721Test.setMonster(
        owner.address,
        200,
        ethers.BigNumber.from("5776272187679102680360502204526423446575382528")
      );
      // kind: 0, hash: 0, species:1, pri_type: 3, second_type: 4, [90, 80, 70, 60, 50, 40, 30], 1100
      await bcm721Test.setMonster(
        addr1.address,
        300,
        ethers.BigNumber.from("5776272187679102680360502283789776888296112128")
      );
      await bcm721Test.setMonster(
        owner.address,
        400,
        ethers.BigNumber.from("5776272187679102680360502283789776888296112128")
      );
      // kind: 0, hash: 0, species:1, pri_type: 5, second_type: 4, [90, 80, 70, 60, 50, 40, 30], 600
      await bcm721Test.setMonster(
        owner.address,
        600,
        ethers.BigNumber.from("5820873678076163926643573684306276592344104960")
      );
      // kind: 0, hash: 0, species:3, pri_type: 5, second_type: 4, [90, 80, 70, 60, 50, 40, 30], 600
      await bcm721Test.setMonster(
        owner.address,
        800,
        ethers.BigNumber.from("5776272187679102680360502247760979869332144128")
      );
    });

    it("ensure block invalid catching power", async function () {
      await expect(bcm721Test.catchMonster(12345, 40, 0)).to.be.revertedWith(
        "invalid_cp"
      );
    });

    it("ensure player is the owner of support toke id", async function () {
      await expect(
        bcm721Test.catchMonster(12345, 40, 100, {
          value: ethers.utils.parseEther("0.0444"),
        })
      ).to.be.revertedWith("not_support_owner");
    });

    it("unsuccess case with no assistant, no boost", async function () {
      // stats: 10(hp), 9, 8, 7, 6, 5
      // success rate: 61 due to decimal num % 100 =  61
      await bcmSettingsTest.setRandomValue(ethers.BigNumber.from(
        "0xa09080706050000000000000000000000000000000000000000000000000029"
      ));
      
      await expect(
        bcm721Test.catchMonster(12345, 40, 0, {
          value: ethers.utils.parseEther("0.0444"),
        })
      )
        .to.emit(bcm721Test, "CatchMonsterEvt")
        .withArgs(owner.address, 0, 12345, 0);

      // money should still be deducted
      await expect(await
        bcm721Test.catchMonster(12345, 40, 0, {
          value: ethers.utils.parseEther("0.0444"),
        })
      ).to.changeEtherBalance(owner, ethers.utils.parseEther("-0.0444"));
    });

    it("success case with boost", async function () {
      // stats: 10(hp), 9, 8, 7, 6, 5
      // success rate: 61 due to decimal num % 100 =  61
      await bcmSettingsTest.setRandomValue(ethers.BigNumber.from(
        "0xa09080706050000000000000000000000000000000000000000000000000029"
      ));
      
      // 0.00222 for each percentage
      await expect(
        bcm721Test.catchMonster(12345, 40, 0, {
          value: ethers.utils.parseEther("0.04662"),
        })
      )
        .to.emit(bcm721Test, "CatchMonsterEvt")
        .withArgs(owner.address, 268, 12345, ethers.BigNumber.from("302698519232059622478803813149524448290259132943366451363840"));
    
      expect(await bcm721Test.tokenURI(268)).to.equal(
        "https://bcmhunt.com/erc/721/monster/268"
      );

      // no effect for more than 70 (due to support type)
      // stats: 10(hp), 9, 8, 7, 6, 5
      // success rate: 75 due to decimal num % 100 =  75
      await bcmSettingsTest.setRandomValue(ethers.BigNumber.from(
        "0xa09080706050000000000000000000000000000000000000000000000000037"
      ));

      await expect(
        bcm721Test.catchMonster(12345, 40, 0, {
          value: ethers.utils.parseEther("2"),
        })
      )
        .to.emit(bcm721Test, "CatchMonsterEvt")
        .withArgs(owner.address, 0, 12345, 0);
    });

    it("unsuccess case with NOT matched level boost assistant but correct type", async function () {
      // stats: 10(hp), 9, 8, 7, 6, 5
      // success rate: 61 due to decimal num % 100 =  61
      await bcmSettingsTest.setRandomValue(ethers.BigNumber.from(
        "0xa09080706050000000000000000000000000000000000000000000000000029"
      ));

      // should be no effective
      await expect(
        bcm721Test.catchMonster(12345, 40, 200, {
          value: ethers.utils.parseEther("0.0444"),
        })
      )
        .to.emit(bcm721Test, "CatchMonsterEvt")
        .withArgs(owner.address, 0, 12345, 0);
    });  

    it("unsuccess case with assistant's exp > max exp", async function () {
      // stats: 10(hp), 9, 8, 7, 6, 5
      // success rate: 61 due to decimal num % 100 =  61
      await bcmSettingsTest.setRandomValue(ethers.BigNumber.from(
        "0xa09080706050000000000000000000000000000000000000000000000000029"
      ));

      // should be no effective
      await expect(
        bcm721Test.catchMonster(12345, 40, 400, {
          value: ethers.utils.parseEther("0.0444"),
        })
      )
        .to.emit(bcm721Test, "CatchMonsterEvt")
        .withArgs(owner.address, 0, 12345, 0);
    });

    it("success case with assistant matching exp range", async function () {
      // stats: 10(hp), 9, 8, 7, 6, 5
      // success rate: 75 due to decimal num % 100 =  75
      await bcmSettingsTest.setRandomValue(ethers.BigNumber.from(
        "0xa09080706050000000000000000000000000000000000000000000000000037"
      ));

      await expect(
        bcm721Test.catchMonster(12345, 40, 600, {
          value: ethers.utils.parseEther("0.0444"),
        })
      )
        .to.emit(bcm721Test, "CatchMonsterEvt")
        .withArgs(owner.address, 268, 12345, ethers.BigNumber.from("302698519232059622478803813149524448290259132943366451363840"));
 

      // stats: 10(hp), 9, 8, 7, 6, 5
      // success rate: 76 due to decimal num % 100 =  76
      await bcmSettingsTest.setRandomValue(ethers.BigNumber.from(
        "0xa09080706050000000000000000000000000000000000000000000000000038"
      ));
      // should be no effective for more than 75
      await expect(
        bcm721Test.catchMonster(12345, 40, 600, {
          value: ethers.utils.parseEther("0.0444"),
        })
      )
        .to.emit(bcm721Test, "CatchMonsterEvt")
        .withArgs(owner.address, 0, 12345, 0);

      // event push - can only reach 85
      // success rate: 86 due to decimal num % 100 =  86
      await bcmSettingsTest.setRandomValue(ethers.BigNumber.from(
        "0xa09080706050000000000000000000000000000000000000000000000000042"
      ));
      // should be no effective for more than 85
      await expect(
        bcm721Test.catchMonster(12345, 40, 600, {
          value: ethers.utils.parseEther("2"),
        })
      )
        .to.emit(bcm721Test, "CatchMonsterEvt")
        .withArgs(owner.address, 0, 12345, 0);

    });

    it("success rate with matching exp range + type assistant", async function () {
      // stats: 10(hp), 9, 8, 7, 6, 5
      // success rate: 76 due to decimal num % 100 =  76
      await bcmSettingsTest.setRandomValue(ethers.BigNumber.from(
        "0xa09080706050000000000000000000000000000000000000000000000000038"
      ));

      await expect(
        bcm721Test.catchMonster(12345, 40, 800, {
          value: ethers.utils.parseEther("0.0444"),
        })
      )
        .to.emit(bcm721Test, "CatchMonsterEvt")
        .withArgs(owner.address, 268, 12345, ethers.BigNumber.from("302698519232059622478803813149524448290259132943366451363840"));
    
      // stats: 10(hp), 9, 8, 7, 6, 5
      // success rate: 91 due to decimal num % 100 = 91
      await bcmSettingsTest.setRandomValue(ethers.BigNumber.from(
        "0xa09080706050000000000000000000000000000000000000000000000000047"
      ));
      // should be no effective for more than 75
      await expect(
        bcm721Test.catchMonster(12345, 40, 800, {
          value: ethers.utils.parseEther("0.0444"),
        })
      )
        .to.emit(bcm721Test, "CatchMonsterEvt")
        .withArgs(owner.address, 0, 12345, 0);
    });

    it("success case with both assistant + boost", async function () {
      // stats: 10(hp), 9, 8, 7, 6, 5
      // success rate: 91 due to decimal num % 100 = 91
      await bcmSettingsTest.setRandomValue(ethers.BigNumber.from(
        "0xa09080706050000000000000000000000000000000000000000000000000047"
      ));

      // 0.00222 for each percentage
      await expect(
        bcm721Test.catchMonster(12345, 40, 800, {
          value: ethers.utils.parseEther("0.04662"),
        })
      )
        .to.emit(bcm721Test, "CatchMonsterEvt")
        .withArgs(owner.address, 268, 12345, ethers.BigNumber.from("302698519232059622478803813149524448290259132943366451363840"));
    });

    it("catch using bcmc to boost and assistant", async function () {
      // stats: 10(hp), 9, 8, 7, 6, 5
      // success rate: 61 due to decimal num = 61
      let randomNum = ethers.BigNumber.from(
        "0xa09080706050000000000000000000000000000000000000000000000000029"
      );
      await bcmSettingsTest.setRandomValue(randomNum);
      let requiredAmount = ethers.utils.parseEther(`${0.00222 + 0.0444}`); // 0.00222 for one percent in chain currency
      // convert to bcmc
      let payValue = ethers.BigNumber.from(requiredAmount).mul(await bcmc20Instance.exchangeRate()).div(10000);
      // low balance
      await expect(
        bcmc20Instance
          .connect(addr1)
          .catchMonsterByBCMC(payValue, 12345, 40, 300)
      ).to.be.revertedWith("ERC20: transfer amount exceeds balance");
      await bcmc20Instance.transfer(addr1.address, payValue);
      expect(await bcmc20Instance.balanceOf(addr1.address)).to.equal(payValue);

      // success
      await expect(
        bcmc20Instance
          .connect(addr1)
          .catchMonsterByBCMC(payValue, 12345, 40, 0)
      )
        .to.emit(bcm721Test, "CatchMonsterEvt")
        .withArgs(addr1.address, 268, 12345, ethers.BigNumber.from("302698519232059622478803813149524448290259132943366451363840"));
      expect(await bcmc20Instance.balanceOf(addr1.address)).to.equal(0);
    });
  });

  describe("BCM Battle Tests", function () {
    beforeEach(async function () {
      // add signer role
      await bcmSettingsTest.grantRole(
        bcmSettingsTest.SIGNER_ROLE(),
        "0x8FB58D8a64a579CfcA349b8b34B69b48FC9C0CB2"
      );
      // add a monster
      // kind: 0, hash: 0, species:1, pri_type: 3, second_type: 4, [90, 80, 70, 60, 50, 40], 0
      await bcm721Test.setMonster(
        owner.address,
        100,
        ethers.BigNumber.from("5776272187679102680360502204526423446575382528")
      );
      // kind: 0, hash: 0, species:1, pri_type: 3, second_type: 4, [90, 80, 70, 60, 50, 40, 30], 20
      await bcm721Test.setMonster(
        addr1.address,
        200,
        ethers.BigNumber.from("5776272187679102680360502205967575327333941248")
      );
    });

    it("ensure the expiry time work", async function () {
      // d2 timestamp = 123
      await expect(
        bcm721Test.battleMonster(
          9160815,
          100,
          ethers.BigNumber.from(
            "6277101793846746257071906151513516049966672347613368680448"
          ),
          ethers.BigNumber.from(
            "772083513452561733952142381421463907644053094276508013297664"
          ),
          "0xbf10cf5289ac0d27a62abd5a990226dbc69433064bb5f86d21e23f052a066de9051ddc356b9687e472d341e8ff48159e1767f5d8267b598d79b7cb625fce27791c"
        )
      ).to.be.revertedWith("expiry_time");
    });

    it("ensure block invalid owner", async function () {
      await bcmSettingsTest.setBattleSignExpiryTime(ethers.BigNumber.from(2).pow(32));
      await expect(
        bcm721Test.battleMonster(
          9160823,
          200,
          ethers.BigNumber.from(
            "6277101793846746257071906151513516049966672347613368680448"
          ),
          ethers.BigNumber.from(
            "102222320986011472392835264382416229874229004618201145773679366373376"
          ),
          "0x5dd3f420c5904c5907f5532f270c1f80e582943d1ea54d51111d8ab512e31af9793fda756d19e9e816a79d7024c56f94be79cb9f671f82aa5bef5cbbb4a2a3de1b"
        )
      ).to.be.revertedWith("invalid_owner");
    });

    it("ensure block invalid chain", async function () {
      // d2 chain id set to 100
      await bcmSettingsTest.setBattleSignExpiryTime(ethers.BigNumber.from(2).pow(32));
      await expect(
        bcm721Test.battleMonster(
          9160837,
          100,
          ethers.BigNumber.from(
            "6277101793846746257071906151513516049966672347613368680448"
          ),
          ethers.BigNumber.from(
            "102222320986011472392835264416104184199401912501075231909424419307520"
          ),
          "0xb4bede6ed95af41eac4f217aba9f8491358a8a55548bb58bdb872fa0b1cbac5956d55e95912b4d2a65e4df26c2f1457b59214271ba82d08e995007b4e934e3f41c"
        )
      ).to.be.revertedWith("invalid_chain");
    });

    it("block mismatch mon id between signed message vs param", async function () {
      await bcmSettingsTest.setBattleSignExpiryTime(ethers.BigNumber.from(2).pow(32));
      // d1: battle_id = 1, mon_id = 100, kill_rate = 40, exp = 230, reward ratio = 100
      await expect(
        bcm721Test.connect(addr1).battleMonster(
          9160852,
          200,
          ethers.BigNumber.from(
            "6277101793846746257071906159277875976917979753991962361856"
          ),
          ethers.BigNumber.from(
            "102222320986011472392835264837033472080602791805269621302521696878592"
          ),
          "0x30a8dafc34fbfe1418ca12695487724949bea7a7f6af642703ae2aaad6d8edfb67ecc360e57eab11172858d8ca317d8262db7182cd6a43239bd8e7080c373b1e1b"
        )
      ).to.be.revertedWith("invalid_mon_id");
    });

    it("block player with BCMC balance < battle requirement", async function () {
      await bcmSettingsTest.setBattleSignExpiryTime(ethers.BigNumber.from(2).pow(32));
      // battle_id = 1, mon_id = 200, species = 40, kill_rate = 40, exp = 230
      await expect(
        bcm721Test.connect(addr1).battleMonster(
          9160935,
          200,
          ethers.BigNumber.from(
            "6277101793846746257071906167200692228344413513346357395456"
          ),
          ethers.BigNumber.from(
            "102222320986011472392835264837033472080602791805269621302521696878592"
          ),
          "0x754713c3c0a31984eab30962306621394b7430c9e1ec6c537088f4d88c265bc0219caf5cad3637bd400b18a4db7f8bf4482b6f7ca47d8c2237e4409febdf331b1c"
        )
      ).to.be.revertedWith("invalid_br");
    });

    it("block too high reward ratio", async function () {
      await bcmSettingsTest.setRewardRatioMax(50);
      // battle_id = 1, mon_id = 200, species = 40, kill_rate = 40, exp = 230, reward ratio = 100
      await expect(
        bcm721Test.connect(addr1).battleMonster(
          9160935,
          200,
          ethers.BigNumber.from(
            "6277101793846746257071906167200692228344413513346357395456"
          ),
          ethers.BigNumber.from(
            "102222320986011472392835264837033472080602791805269621302521696878592"
          ),
          "0x754713c3c0a31984eab30962306621394b7430c9e1ec6c537088f4d88c265bc0219caf5cad3637bd400b18a4db7f8bf4482b6f7ca47d8c2237e4409febdf331b1c"
        )
      ).to.be.revertedWith("invalid_ratio");
    });

    it("lose battle and the monster gets killed", async function () {
      await bcmc20Instance.transfer(addr1.address, ethers.utils.parseEther("10.0"));
      await bcmc20Instance.transfer(bcm721Test.address, ethers.utils.parseEther("100.0"));
      await bcmSettingsTest.setBattleSignExpiryTime(ethers.BigNumber.from(2).pow(32));
      const randomNum = ethers.BigNumber.from("0x01");
      await bcmSettingsTest.setRandomValue(randomNum);
      // species 40, staking require = 10 BCMC, bcmc reward = 8
      // battle_id = 1, mon_id = 200, blk_species = 40, kill_rate = 40, exp = 230, bcmc = 1000
      await expect(
        bcm721Test.connect(addr1).battleMonster(
          9160935,
          200,
          ethers.BigNumber.from(
            "6277101793846746257071906167200692228344413513346357395456"
          ),
          ethers.BigNumber.from(
            "102222320986011472392835264837033472080602791805269621302521696878592"
          ),
          "0x754713c3c0a31984eab30962306621394b7430c9e1ec6c537088f4d88c265bc0219caf5cad3637bd400b18a4db7f8bf4482b6f7ca47d8c2237e4409febdf331b1c"
        )
      ).to.emit(bcm721Test, "Transfer")
      .withArgs(addr1.address, "0x0000000000000000000000000000000000000000", 200);
      // no change in bcmc
      expect(await bcmc20Instance.balanceOf(addr1.address)).to.equal(ethers.utils.parseEther("10.0"));
    })

    it("pay insurance to survive", async function () {
      // send some eth to pay insurance
      await owner.sendTransaction({to: bcm721Test.address, value: ethers.utils.parseEther("50.0")});
      // send some token to satisfy staking requirement
      await bcmc20Instance.transfer(addr1.address, ethers.utils.parseEther("10.0"));
      // send bcmc to erc721 to pay battle reward
      await bcmc20Instance.transfer(bcm721Test.address, ethers.utils.parseEther("100.0"));
      await bcmSettingsTest.setBattleSignExpiryTime(ethers.BigNumber.from(2).pow(32));
      const randomNum = ethers.BigNumber.from("0x01");
      await bcmSettingsTest.setRandomValue(randomNum);
      // species 40: staking requirement = 10, insurance = 35$ => 35/451 = 0.07761 ETH
      // battle_id = 1, mon_id = 200, species = 40, kill_rate = 40, exp = 230
      const insuranceValue = ethers.utils.parseEther("0.07761");
      await expect(await 
        bcm721Test.connect(addr1).battleMonster(
          9160935,
          200,
          ethers.BigNumber.from(
            "6277101793846746257071906167200692228344413513346357395456"
          ),
          ethers.BigNumber.from(
            "102222320986011472392835264837033472080602791805269621302521696878592"
          ),
          "0x754713c3c0a31984eab30962306621394b7430c9e1ec6c537088f4d88c265bc0219caf5cad3637bd400b18a4db7f8bf4482b6f7ca47d8c2237e4409febdf331b1c"
        ,{value: insuranceValue})
      ).to.changeEtherBalance(bcm721Test, insuranceValue);
      // no change in bcmc
      expect(await bcmc20Instance.balanceOf(addr1.address)).to.equal(ethers.utils.parseEther("10.0"));
      // token is there
      expect(await bcm721Test.ownerOf(200)).to.equal(addr1.address);
    })

    it("win battle and get bcmc", async function () {
      await bcmc20Instance.transfer(addr1.address, ethers.utils.parseEther("10.0"));
      await bcmc20Instance.transfer(bcm721Test.address, ethers.utils.parseEther("100.0"));
      await bcmSettingsTest.setBattleSignExpiryTime(ethers.BigNumber.from(2).pow(32));
      const randomNum = ethers.BigNumber.from("0x29");
      await bcmSettingsTest.setRandomValue(randomNum);
      // species 40: staking requirement = 10, bcmc reward = 8
      // battle_id = 1, mon_id = 200, species: 40, kill_rate = 40, exp = 230
      await expect(
        bcm721Test.connect(addr1).battleMonster(
          9161027,
          200,
          ethers.BigNumber.from(
            "6277101793846746257071906167200692227606543750397975330816"
          ),
          ethers.BigNumber.from(
            "102222320986011472392835264837033472080602791805269621302521696878592"
          ),
          "0xbdecd3ef3ead4e47c861fe91cb5783990e1c6589d2f5e0c5e20c7b448d6197a7392fbe506937744d8e0da566b80a035b289fe787c9239bc0fd188a0af2399b1e1c"
        )
      ).to.emit(bcm721Test, "BattleMonsterEvt")
      .withArgs(addr1.address, ethers.BigNumber.from("0x01000000e60000000000000000000000000000000000000000"), ethers.utils.parseEther("8.0"), 9161027);
      // receive bcmc 
      expect(await bcmc20Instance.balanceOf(addr1.address)).to.equal(ethers.utils.parseEther("18.0"));
    })

    it("win battle and get x1.75 reward", async function () {
      await bcmc20Instance.transfer(addr1.address, ethers.utils.parseEther("10.0"));
      await bcmc20Instance.transfer(bcm721Test.address, ethers.utils.parseEther("100.0"));
      await bcmSettingsTest.setBattleSignExpiryTime(ethers.BigNumber.from(2).pow(32));
      const randomNum = ethers.BigNumber.from("0x29");
      await bcmSettingsTest.setRandomValue(randomNum);
      // species 40: staking requirement = 10, bcmc reward = 8
      // battle_id = 1, mon_id = 200, species: 40, kill_rate = 40, exp = 230, reward ratio = 175
      await expect(
        bcm721Test.connect(addr1).battleMonster(
          9161146,
          200,
          ethers.BigNumber.from(
            "6277101793846746257071906167200692227606543750397980246016"
          ),
          ethers.BigNumber.from(
            "102222320986011472392835264837033472080602791805269621302521696878592"
          ),
          "0x82add393df9b61f81f4e5c3e0871ddb91f65c1877da9bdc8c407b13bbd379e6418b70369732172ba042b01e750279f4b6788b63dadd5dc2543e9bb7b01d0ff0c1b"
        )
      ).to.emit(bcm721Test, "BattleMonsterEvt")
      .withArgs(addr1.address, ethers.BigNumber.from("0x01000000e60000000000000000000000000000000000000000"), ethers.utils.parseEther("14.0"), 9161146);
      // receive bcmc 
      expect(await bcmc20Instance.balanceOf(addr1.address)).to.equal(ethers.utils.parseEther("24.0"));      
    });

    it("Late winner win will not get reward", async function () {
      await bcmc20Instance.transfer(addr1.address, ethers.utils.parseEther("10.0"));
      await bcmc20Instance.transfer(bcm721Test.address, ethers.utils.parseEther("100.0"));
      await bcmSettingsTest.setBattleSignExpiryTime(ethers.BigNumber.from(2).pow(32));
      const randomNum = ethers.BigNumber.from("0x29");
      await bcmSettingsTest.setRandomValue(randomNum);
      // species 40: staking requirement = 10, bcmc reward = 8
      // battle_id = 1, mon_id = 200, species: 40, kill_rate = 40, exp = 230
      await expect(
        bcm721Test.connect(addr1).battleMonster(
          9161027,
          200,
          ethers.BigNumber.from(
            "6277101793846746257071906167200692227606543750397975330816"
          ),
          ethers.BigNumber.from(
            "102222320986011472392835264837033472080602791805269621302521696878592"
          ),
          "0xbdecd3ef3ead4e47c861fe91cb5783990e1c6589d2f5e0c5e20c7b448d6197a7392fbe506937744d8e0da566b80a035b289fe787c9239bc0fd188a0af2399b1e1c"
        )
      ).to.emit(bcm721Test, "BattleMonsterEvt")
      .withArgs(addr1.address, ethers.BigNumber.from("0x01000000e60000000000000000000000000000000000000000"), ethers.utils.parseEther("8.0"), 9161027);
      // receive bcmc 
      expect(await bcmc20Instance.balanceOf(addr1.address)).to.equal(ethers.utils.parseEther("18.0"));

      // battle_id = 2
      await expect(
        bcm721Test.connect(addr1).battleMonster(
          9161027,
          200,
          ethers.BigNumber.from(
            "12554203529233427020907695590408358643708899194862009843712"
          ),
          ethers.BigNumber.from(
            "102222320986011472392835264837033472080602791805269621302521696878592"
          ),
          "0x4eff32a914210573058ae1810b14efdbbbd0b4c6ae4055392fff7bcd771490413fac99a04e1c9d2abd64271653543c85024590197d4ac2ef8e8ad61a598797791b"
        )
      ).to.emit(bcm721Test, "BattleMonsterEvt")
      .withArgs(addr1.address, ethers.BigNumber.from("0x02000000e60000000000000000000000000000000000000000"), ethers.utils.parseEther("8.0"), 9161027);
      // receive bcmc 
      expect(await bcmc20Instance.balanceOf(addr1.address)).to.equal(ethers.utils.parseEther("26.0"));

      // battle_id = 3
      await expect(
        bcm721Test.connect(addr1).battleMonster(
          9161027,
          200,
          ethers.BigNumber.from(
            "18831305264620107784743485013616025059811254639326044356608"
          ),
          ethers.BigNumber.from(
            "102222320986011472392835264837033472080602791805269621302521696878592"
          ),
          "0xc098cccd40262d50f538f806e2fab52cb44c1036a68debfdae4cbb1db906b10322ab7a2924bda40c2383e85ac17175039f057e126ae2b8e95f60c1cab9f5dd3a1c"
        )
      ).to.emit(bcm721Test, "BattleMonsterEvt")
      .withArgs(addr1.address, ethers.BigNumber.from("0x03000000e60000000000000000000000000000000000000000"), 0, 9161027);
      // no reward
      expect(await bcmc20Instance.balanceOf(addr1.address)).to.equal(ethers.utils.parseEther("26.0"));
    });

    it("buy insurance using bcmc", async function () {
      // send bcmc to erc721 to pay battle reward
      await bcmc20Instance.transfer(bcm721Test.address, ethers.utils.parseEther("100.0"));
      await bcmSettingsTest.setBattleSignExpiryTime(ethers.BigNumber.from(2).pow(32));
      const randomNum = ethers.BigNumber.from("0x01");
      await bcmSettingsTest.setRandomValue(randomNum);
      // send some token to satisfy stake requirement
      await bcmc20Instance.transfer(addr1.address, ethers.utils.parseEther("30.0"));
      // buy insurance
      // species 40: staking requirement = 10, insurance = 35$ => 35/451 = 0.07761 ETH
      // battle_id = 1, mon_id = 200, species = 40, kill_rate = 40, exp = 230
      const insuranceValueInBCMC = ethers.utils.parseEther("0.07761");
      let payValue = ethers.BigNumber.from(insuranceValueInBCMC).mul(await bcmc20Instance.exchangeRate()).div(10000);
      await expect(await 
        bcmc20Instance.connect(addr1).battleMonsterByBCMC(
          payValue,
          9160935,
          200,
          ethers.BigNumber.from(
            "6277101793846746257071906167200692228344413513346357395456"
          ),
          ethers.BigNumber.from(
            "102222320986011472392835264837033472080602791805269621302521696878592"
          ),
          "0x754713c3c0a31984eab30962306621394b7430c9e1ec6c537088f4d88c265bc0219caf5cad3637bd400b18a4db7f8bf4482b6f7ca47d8c2237e4409febdf331b1c"
        )
      ).to.emit(bcm721Test, "BattleMonsterEvt")
      .withArgs(addr1.address, ethers.BigNumber.from("0x01000000e60000000000000000000000000000000000000000"), 0, 9160935);
      // new balance
      expect(await bcmc20Instance.balanceOf(addr1.address)).to.equal(ethers.utils.parseEther(`${30-0.7761}`));
      // token is there
      expect(await bcm721Test.ownerOf(200)).to.equal(addr1.address);
    });

  });

  describe("Trade Permit Tests", function () {
    beforeEach(async function () {
      await bcm721Test.grantRole(
        bcm721Test.PARTNER_CONTRACT_ROLE(),
        addr2.address
      );
      // add a token
      // kind: 0, hash: 0, species:1, pri_type: 3, second_type: 4, [90, 80, 70, 60, 50, 40], 0
      await bcm721Test.setMonster(
        addr2.address,
        100,
        ethers.BigNumber.from("5776272187679102680360502204526423446575382528")
      );
    })

    /*
    it("approve using signature", async function () {
      // signagure is hardcoded by this address
      expect(bcm721Test.address).to.equal("0xE3a0cD4B5d37D0c2b9Be107da162e864bC0156F9");
      await expect(await bcm721Test.connect(addr2).permitTrade(addr2.address, owner.address, 100, 1, 1, 10000000000, 0, 
        "0xc81f7ad736008a0ba6c26cba8acf352827c55d4982465d031d6c7108c14400c9752766c8ce4c86a24e8df13d598eba8fd006df86c108adab1bd50092f1fe038d1b")
        ).to.emit(bcm721Test, "Approval")
        .withArgs(addr2.address, owner.address, 100);
      // can't reuse
      await expect(bcm721Test.connect(addr2).permitTrade(addr2.address, owner.address, 100, 1, 1, 10000000000, 0, 
        "0xc81f7ad736008a0ba6c26cba8acf352827c55d4982465d031d6c7108c14400c9752766c8ce4c86a24e8df13d598eba8fd006df86c108adab1bd50092f1fe038d1b")
        ).to.be.revertedWith("used_permit");
    });

    it("cancel the approve permit", async function () {
      // signagure is hardcoded by this address
      expect(bcm721Test.address).to.equal("0x0B8b1b663c57Cc20491dCA0b921a110323920cD5");
      await expect(await bcm721Test.connect(addr2).cancelPermitTrade(addr2.address, 1)
        ).to.emit(bcm721Test, "CancelPermitTradeEvt")
        .withArgs(addr2.address, 1);
      // can't reuse any more
      await expect(bcm721Test.connect(addr2).permitTrade(addr2.address, owner.address, 100, 1, 1, 10000000000, 0, 
        "0x89c14212cbfcd391287f41c812117b267362202c74479bdc26ffc80e40961750796792f1d599e35b74b5e08f1c1fa7000645d5eec3f0aa8df14a9398292c86e61c")
        ).to.be.revertedWith("used_permit");
    });    
    */
  })
});
