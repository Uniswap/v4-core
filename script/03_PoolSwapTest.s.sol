// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Script, console2} from "forge-std/Script.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {PoolSwapTest} from "../src/test/PoolSwapTest.sol";

import "forge-std/console2.sol";

contract DeployPoolSwapTest is Script {
    function setUp() public {}

    function run(address poolManager) public returns (PoolSwapTest testSwapRouter) {
        vm.broadcast();
        testSwapRouter = new PoolSwapTest(IPoolManager(poolManager));
        console2.log("PoolSwapTest", address(testSwapRouter));
    }
}
