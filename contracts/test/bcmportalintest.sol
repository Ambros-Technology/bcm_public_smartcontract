// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.2;

import "./../bcmportalin.sol";

contract BCMPortalInTest is BCMPortalIn {
    function __ERC777_init_unchained() internal override initializer {
        // disable the registration on test;
    }
}
