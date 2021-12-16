// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.2;

import "./../bcmcerc20.sol";

// for testing only
contract BlockchainMonsterCoinTest is BlockchainMonsterCoin {
    string public version;

    function name() public view virtual override returns (string memory) {
        return "test";
    }

    function setVersion(string memory value)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        version = value;
    }
}
