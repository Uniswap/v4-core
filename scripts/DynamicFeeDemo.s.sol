// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/Script.sol';

import {PoolManager} from '../contracts/PoolManager.sol';
import {IPoolManager} from '../contracts/interfaces/IPoolManager.sol';
import {VolatilityOracle} from '../contracts/hooks/VolatilityOracle.sol';
import {Deployers} from '../test/foundry-tests/utils/Deployers.sol';

contract MyScript is Script {
    function run() external {
        vm.startBroadcast();
        uint256 CONTROLLER_FEE = 50000;
        PoolManager manager = new PoolManager(CONTROLLER_FEE);
        vm.stopBroadcast();

        uint256 pk = 0xf53e3747d93eb10180fc46078e1cf55d9f5fa485ce4106d3eb77404204ca8c25;
        console2.log(vm.addr(pk));
        vm.startBroadcast(pk);
        VolatilityOracle dynamicFeeHook = new VolatilityOracle(manager);
        vm.stopBroadcast();

        vm.startBroadcast();
        Deployers deployer = new Deployers();
        uint160 sqrtPriceX96 = 2**96;
        (IPoolManager.PoolKey memory key, bytes32 id) = deployer.createPool(manager, dynamicFeeHook, sqrtPriceX96);
        vm.stopBroadcast();
    }
}
