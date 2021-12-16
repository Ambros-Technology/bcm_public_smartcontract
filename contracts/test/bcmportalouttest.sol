// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.2;

import "./../bcmportalout.sol";

contract BCMPortalOutTest is BCMPortalOut {
    function __ERC777_init_unchained() internal override initializer {
        // disable the registration on test;
    }
}