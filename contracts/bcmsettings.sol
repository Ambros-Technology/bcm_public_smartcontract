// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.2;

// import "hardhat/console.sol";

import "./bcmupgradable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

contract BCMSettings is BCMUpgradable {
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");

    mapping(uint256 => uint256) public speciesSetting1;
    mapping(uint256 => uint256) public speciesSetting2;
    mapping(uint256 => uint256) public blockHashCache; // block => hash
    mapping(uint256 => bool) public markedBattles; // battle id
    mapping(uint256 => uint256) public battleWinCount; // block => count

    uint256 public catchDistribution; // [0 -> x] catch
    uint256 public battleDistribution; // (x->y] battle

    uint256 public chainCurrencyPrice; // in usd cent
    uint256 public battleSignatureExpiryPeriod; // in seconds
    uint256 public rewardRatioMax; // in percentage

    // related contracts
    address public bcmc20Contract;

    // event
    event AdminSetBCMC20ContractEvt(
        address indexed sender,
        address value
    );
    event AdminSetSpeciesSettingEvt(
        address indexed sender,
        uint256 speciesId,
        uint256 setting1,
        uint256 setting2
    );
    event AdminSetBlockDistributionEvt(
        address indexed sender,
        uint256 catchValue, 
        uint256 battleValue
    );
    event AdminSetChainCurrencyPriceEvt(
        address indexed sender,
        uint256 price
    );
    event AdminSetRewardRatioMaxEvt(
        address indexed sender,
        uint256 value
    );
    event AdminSetBattleSignExpiryEvt(
        address indexed sender,
        uint256 value
    );
    event AdminSetBlockHashEvt(
        address indexed sender,
        uint256 blockNumber,
        uint256 blockHash
    );

    function initialize() public initializer {
        BCMUpgradable.__BCMUpgradable_initialize();
        catchDistribution = 85;
        battleDistribution = 170;
        chainCurrencyPrice = 100; // update accordingly for each chain - USD cent
        battleSignatureExpiryPeriod = 600;
        rewardRatioMax = 275; // in percentage
    }

    function setBCMC20Contract(address value)
        external
        onlyRole(MODERATOR_ROLE)
    {
        bcmc20Contract = value;
        emit AdminSetBCMC20ContractEvt(msg.sender, value);
    }

    function setSpeciesSetting(
        uint256 speciesId,
        uint256 setting1,
        uint256 setting2
    ) external onlyRole(MODERATOR_ROLE) {
        speciesSetting1[speciesId] = setting1;
        speciesSetting2[speciesId] = setting2;
        emit AdminSetSpeciesSettingEvt(msg.sender, speciesId, setting1, setting2);
    }

    function setBlockDistribution(
        uint256 catchValue, 
        uint256 battleValue
    ) external onlyRole(MODERATOR_ROLE) {
        require(battleValue > catchValue, "invalid_params");
        catchDistribution = catchValue;
        battleDistribution = battleValue;
        emit AdminSetBlockDistributionEvt(msg.sender, catchValue, battleValue);
    }

    function setChainCurrencyPrice(
        uint256 price
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        chainCurrencyPrice = price;
        emit AdminSetChainCurrencyPriceEvt(msg.sender, price);
    }

    function setRewardRatioMax(
        uint256 value
    ) external onlyRole(MODERATOR_ROLE) {
        rewardRatioMax = value;
        emit AdminSetRewardRatioMaxEvt(msg.sender, value);
    }

    function setBattleSignExpiryTime(uint256 value)
        external
        onlyRole(MODERATOR_ROLE)
    {
        battleSignatureExpiryPeriod = value;
        emit AdminSetBattleSignExpiryEvt(msg.sender, value);
    }

    function setBlockHash(uint256 blockNumber, uint256 blockHash)
        external
        onlyRole(MODERATOR_ROLE)
    {
        blockHashCache[blockNumber] = blockHash;
        emit AdminSetBlockHashEvt(msg.sender, blockNumber, blockHash);
    }

    // internal
    // not truely randon but good enough for our case
    function _random(address sender, uint256 nonce)
        internal
        view
        virtual
        returns (uint256)
    {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        block.difficulty,
                        block.timestamp,
                        blockhash(block.number - 1),
                        sender,
                        nonce
                    )
                )
            );
    }

    function _genBlockhash(uint256 blockNumber)
        internal
        virtual
        returns (uint256 bh)
    {
        bh = blockHashCache[blockNumber];
        if (bh == 0) {
            bh = uint64(uint256(blockhash(blockNumber)));
            blockHashCache[blockNumber] = bh;
        }
        require(bh > 0, "invalid_block");
    }

    function _splitSignature(bytes memory sig)
        internal
        pure
        returns (
            bytes32 r,
            bytes32 s,
            uint8 v
        )
    {
        require(sig.length == 65, "invalid_signature");
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }

    function _getMessageHash(
        uint256 blockNumber,
        uint256 d1,
        uint256 d2
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    keccak256(abi.encodePacked(blockNumber, d1, d2))
                )
            );
    }

    // partner call e.g BCMERC721
    function genGene(
        address sender,
        uint256 amount,
        uint256 blockNumber,
        uint256 current_count,
        uint256 blk_species,
        uint256 support_type,
        uint256 support_exp
    ) external virtual onlyRole(PARTNER_CONTRACT_ROLE) returns (uint256) {
        uint256 speciesStas1 = speciesSetting1[blk_species];
        uint256 speciesStas2 = speciesSetting2[blk_species];
        uint256 bh = _genBlockhash(blockNumber);

        // check catch
        require(uint8(bh) <= catchDistribution, "not_catch_block");

        // verify input species
        require(
            speciesStas1 > 0 &&
                bh >= (speciesStas1 >> 192) &&
                bh <= uint256(uint64(speciesStas1 >> 128)),
            "invalid_species"
        );

        // verify min catch power
        uint256 min_cp = (uint256(uint32(speciesStas2 >> 224)) *
            (uint256(10)**18)) / chainCurrencyPrice;
        require(amount >= min_cp, "invalid_cp");

        // check limit
        require(
            current_count < uint256(uint16(speciesStas2 >> 208)),
            "limit_reach"
        );

        // check success
        uint256 sr = uint256(uint8(speciesStas2 >> 200)); // 0 => 100
        // boost by money
        sr += (amount - min_cp) / (uint256(uint32(speciesStas2 >> 168) * (uint256(10)**18)) / chainCurrencyPrice);
        
        // check assist level
        if (uint256(uint8(speciesStas2 >> 160)) > 0) {
            // if level within range
            if (support_exp >= uint256(uint32(speciesStas2 >> 128)) && support_exp <= uint256(uint32(speciesStas2 >> 96))) {
                // also match type
                if (uint256(uint8(speciesStas2 >> 160)) == support_type) {
                    sr += 30;
                } else {
                    sr += 15;
                    // match can reach = 85%
                    if (sr > 85) {
                        sr = 85;
                    }
                }
            } else {
                // not satisfy
                if (sr > 70) {
                    sr = 70;
                }
            }
        }

        uint256 randValue = _random(sender, current_count);
        if (randValue % 100 <= sr) {
            // success case
            // gen stats
            uint256 gene = blockNumber << 184;
            gene |= blk_species << 152; // set species
            gene |= blk_species << 144;
            gene |= blk_species << 136;
            gene |=
                uint256(
                    uint8(speciesStas2 >> 88) + (uint8(randValue >> 248) % 12)
                ) <<
                128; // hp
            gene |=
                uint256(
                    uint8(speciesStas2 >> 80) + (uint8(randValue >> 240) % 12)
                ) <<
                120; // atk
            gene |=
                uint256(
                    uint8(speciesStas2 >> 72) + (uint8(randValue >> 232) % 12)
                ) <<
                112; // def
            gene |=
                uint256(
                    uint8(speciesStas2 >> 64) + (uint8(randValue >> 224) % 12)
                ) <<
                104; // spa
            gene |=
                uint256(
                    uint8(speciesStas2 >> 56) + (uint8(randValue >> 216) % 12)
                ) <<
                96; // spd
            gene |=
                uint256(
                    uint8(speciesStas2 >> 48) + (uint8(randValue >> 208) % 12)
                ) <<
                88; // sp
            return gene;
        } else {
            return 0;
        }
    }

    // partner call e.g BCMERC721
    function genBattle(
        address sender,
        uint256 amount,
        uint256 monId,
        uint256 blockNumber,
        uint256 d1,
        uint256 d2,
        bytes memory signature
    )
        external virtual
        onlyRole(PARTNER_CONTRACT_ROLE)
        returns (uint256 result, uint256 bcmc)
    {
        // check timestamp
        require(
            (d2 >> 192) > block.timestamp ||
                (block.timestamp - (d2 >> 192)) < battleSignatureExpiryPeriod,
            "expiry_time"
        );

        // check chainid
        require(uint64(d2 >> 128) == block.chainid, "invalid_chain");
        
        uint256 battleId = uint256(uint64(d1 >> 192));
        require(isValid(blockNumber, d1, d2, signature), "invalid_signer");
        require(markedBattles[battleId] == false, "used_battle_id");
        require(uint256(uint64(d1 >> 96)) == monId, "invalid_mon_id");
        require(uint256(uint16(d1 >> 16)) <= rewardRatioMax, "invalid_ratio");

        uint256 blkSpeciesStas1 = speciesSetting1[uint32(d1 >> 160)];
        require(
            IERC20Upgradeable(bcmc20Contract).balanceOf(sender) >=
                ((uint256(uint32(blkSpeciesStas1 >> 80)) * (uint256(10)**18)) / 1000),
            "invalid_br"
        );

        result = uint256(uint64(battleId)) << 192; // battle id
        result |= (uint256(uint32(d1 >> 32))) << 160; // gain exp

        uint256 kr = uint256(uint32(d1 >> 64));
        if (kr > 0) {
            // lose - check if insurance is purchased
            if (amount < (uint256(uint32(blkSpeciesStas1)) * (uint256(10)**18) / chainCurrencyPrice)) {
                if (_random(sender, d1) % 100 <= kr) {
                    result |= (1 << 128); // killed
                }
            }
        } else {
            // win
            if (battleWinCount[blockNumber] < uint256(uint16(blkSpeciesStas1 >> 32))) {
                battleWinCount[blockNumber] += 1;
                bcmc = uint256(uint16(d1 >> 16)) * ((uint256(uint32(blkSpeciesStas1 >> 48)) * (uint256(10)**18)) / 1000) / 100;
            }
        }

        markedBattles[battleId] = true; // prevent reuse this txn
    }

    // public info
    function getSpeciesSetting(uint256 speciesId)
        external
        view
        returns (uint256 s1, uint256 s2)
    {
        s1 = speciesSetting1[speciesId];
        s2 = speciesSetting2[speciesId];
    }

    function isValid(
        uint256 blockNumber,
        uint256 d1,
        uint256 d2,
        bytes memory signature
    ) public view returns (bool) {
        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(signature);
        bytes32 messageHash = _getMessageHash(blockNumber, d1, d2);
        return hasRole(SIGNER_ROLE, ecrecover(messageHash, v, r, s));
    }

    function getFixedSpeciesSetting(uint256 speciesId)
        external
        view
        returns (
            uint256 bh_start,
            uint256 bh_end,
            uint256 primary_type,
            uint256 secondary_type
        )
    {
        uint256 s = speciesSetting1[speciesId];
        bh_start = uint256(uint64(s >> 192));
        bh_end = uint256(uint64(s >> 128));
        primary_type = uint256(uint8(s >> 120));
        secondary_type = uint256(uint8(s >> 112));
    }

    function getBattleSpeciesSetting(uint256 speciesId) 
        external
        view
        returns (
            uint256 bcmcStakingRequirement,
            uint256 bcmcReward,
            uint256 totalRewardedWinner,
            uint256 insuranceFee
        )
    {
        uint256 s = speciesSetting1[speciesId];
        bcmcStakingRequirement = uint256(uint32(s >> 80)) * (uint256(10)**18) / 1000;
        bcmcReward = uint256(uint32(s >> 48)) * (uint256(10)**18) / 1000;
        totalRewardedWinner = uint256(uint16(s >> 32));
        insuranceFee = uint256(uint32(s)) * (uint256(10)**18) / chainCurrencyPrice;
    }

    function getCatchSpeciesSetting(uint256 speciesId)
        external
        view
        returns (
            uint256 minCP,
            uint16 blkLimit,
            uint8 startSuccessRate,
            uint256 costPerSRPercentage,
            uint8 assistantType,
            uint32 assistantMinExp,
            uint32 assistantMaxExp
        )
    {
        uint256 s = speciesSetting2[speciesId];
        minCP = (uint256(uint32(s >> 224)) * (uint256(10)**18)) / chainCurrencyPrice;
        blkLimit = uint16(s >> 208);
        startSuccessRate = uint8(s >> 200);
        costPerSRPercentage = (uint256(uint32(s >> 168) * (uint256(10)**18)) / chainCurrencyPrice);
        assistantType = uint8(s >> 160);
        assistantMinExp = uint32(s >> 128);
        assistantMaxExp = uint32(s >> 96);
    }

    function getBattleStats(uint256 speciesId)
        external
        view
        returns (
            uint8 hp,
            uint8 atk,
            uint8 def,
            uint8 spa,
            uint8 spd,
            uint8 sp
        )
    {
        uint256 s = speciesSetting2[speciesId];
        hp = uint8(s >> 88);
        atk = uint8(s >> 80);
        def = uint8(s >> 72);
        spa = uint8(s >> 64);
        spd = uint8(s >> 56);
        sp = uint8(s >> 48);
    }
}
