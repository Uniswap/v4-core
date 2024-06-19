// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/console2.sol";
import "forge-std/Script.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";

import "forge-std/console2.sol";

contract DeployPoolManager is Script {
    function setUp() public {}

    function run(uint256 controllerGasLimit) public returns (IPoolManager manager) {
        vm.startBroadcast();

        manager = new PoolManager(controllerGasLimit);
        console2.log("PoolManager", address(manager));

        vm.stopBroadcast();
    }
}
