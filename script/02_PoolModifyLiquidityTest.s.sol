// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Script, console2} from "forge-std/Script.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {PoolModifyLiquidityTest} from "../src/test/PoolModifyLiquidityTest.sol";

import "forge-std/console2.sol";

contract DeployPoolModifyLiquidityTest is Script {
    function setUp() public {}

    function run(address poolManager) public returns (PoolModifyLiquidityTest testModifyRouter) {
        vm.broadcast();
        testModifyRouter = new PoolModifyLiquidityTest(IPoolManager(poolManager));
        console2.log("PoolModifyLiquidityTest", address(testModifyRouter));
    }
}
