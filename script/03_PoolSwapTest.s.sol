// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Script, console2} from "forge-std/Script.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {PoolSwapTest} from "../src/test/PoolSwapTest.sol";

contract PoolSwapTestScript is Script {
    address poolManager = 0xc021A7Deb4a939fd7E661a0669faB5ac7Ba2D5d6;
    function setUp() public {}

    function run() public {
        vm.broadcast();
        new PoolSwapTest(IPoolManager(poolManager));
    }
}
