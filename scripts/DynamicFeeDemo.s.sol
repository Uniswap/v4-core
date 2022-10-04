// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/Script.sol';
import 'forge-std/console2.sol';

import {TickMath} from '../contracts/libraries/TickMath.sol';
import {Currency} from '../contracts/libraries/CurrencyLibrary.sol';
import {PoolModifyPositionTest} from '../contracts/test/PoolModifyPositionTest.sol';
import {PoolSwapTest} from '../contracts/test/PoolSwapTest.sol';
import {TestERC20} from '../contracts/test/TestERC20.sol';
import {PoolManager} from '../contracts/PoolManager.sol';
import {IPoolManager} from '../contracts/interfaces/IPoolManager.sol';
import {VolatilityOracle} from '../contracts/hooks/VolatilityOracle.sol';
import {Deployers} from '../test/foundry-tests/utils/Deployers.sol';

contract MyScript is Script {
    function run() external {
        uint256 deployerKey = vm.envUint('DEPLOYER_KEY');
        address deployerAddress = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);
        uint256 CONTROLLER_FEE = 50000;
        PoolManager manager = new PoolManager(CONTROLLER_FEE);
        vm.stopBroadcast();

        uint256 pk = 0xf53e3747d93eb10180fc46078e1cf55d9f5fa485ce4106d3eb77404204ca8c25;
        console2.log(vm.addr(pk));
        vm.startBroadcast(pk);
        VolatilityOracle dynamicFeeHook = new VolatilityOracle(manager);
        vm.stopBroadcast();

        Deployers deployer = new Deployers();
        vm.startBroadcast(deployerKey);

        uint160 sqrtPriceX96 = 2**96;
        (IPoolManager.PoolKey memory key, bytes32 id) = deployer.createPool(manager, dynamicFeeHook, sqrtPriceX96);
        console2.log('Poolmanager', address(manager));

        TestERC20 tokenA = TestERC20(Currency.unwrap(key.currency0));
        TestERC20 tokenB = TestERC20(Currency.unwrap(key.currency1));
        tokenA.mint(deployerAddress, 10**18);
        tokenB.mint(deployerAddress, 10**18);

        PoolModifyPositionTest addLiquidity = new PoolModifyPositionTest(IPoolManager(address(manager)));
        tokenA.approve(address(addLiquidity), type(uint256).max);
        tokenB.approve(address(addLiquidity), type(uint256).max);
        addLiquidity.modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({
                tickLower: TickMath.minUsableTick(60),
                tickUpper: TickMath.maxUsableTick(60),
                liquidityDelta: 10**9
            })
        );

        PoolSwapTest swapTest = new PoolSwapTest(manager);
        tokenA.approve(address(swapTest), type(uint256).max);
        tokenB.approve(address(swapTest), type(uint256).max);

        swapTest.swap(key, IPoolManager.SwapParams(false, 100, 2**96 * 2), PoolSwapTest.TestSettings(true, true));

        swapTest.swap(key, IPoolManager.SwapParams(false, 100, 2**96 * 2), PoolSwapTest.TestSettings(true, true));

        vm.stopBroadcast();
    }
}
