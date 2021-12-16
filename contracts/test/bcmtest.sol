// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.2;

import "./../bcmerc721.sol";
import "./../bcmsettings.sol";

// for testing only
contract BCMSettingsTest is BCMSettings {
    uint256 public randomValue;

    function setRandomValue(uint256 value) public onlyRole(DEFAULT_ADMIN_ROLE) {
        randomValue = value;
    }

    function _random(
        address, /* sender */
        uint256 /* nonce */
    ) internal view override returns (uint256) {
        return randomValue;
    }
}

contract BlockchainMonsterTest is BlockchainMonster {
    function setMonster(
        address owner,
        uint256 tokenId,
        uint256 value
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        monsters[tokenId] = value;
        _mint(owner, tokenId);
    }
}

contract BlockchainMonsterUtil {
    function getChainId() external view returns(uint256) {
        return block.chainid;
    }
}