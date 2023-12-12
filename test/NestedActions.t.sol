// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "./utils/Deployers.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Action} from "../src/test/PoolNestedActionsTest.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";

contract NestedActions is Test, Deployers, GasSnapshot {
    function setUp() public {
        initializeManagerRoutersAndPoolsWithLiq(IHooks(address(0)));
    }
}
