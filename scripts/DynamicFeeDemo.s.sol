// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/Script.sol';
import 'forge-std/console2.sol';

import {TickMath} from '../contracts/libraries/TickMath.sol';
import {Currency} from '../contracts/libraries/CurrencyLibrary.sol';
import {PoolModifyPositionTest} from '../contracts/test/PoolModifyPositionTest.sol';
import {PoolSwapTest} from '../contracts/test/PoolSwapTest.sol';
import {IHooks} from '../contracts/interfaces/IHooks.sol';
import {TestERC20} from '../contracts/test/TestERC20.sol';
import {PoolManager} from '../contracts/PoolManager.sol';
import {IPoolManager} from '../contracts/interfaces/IPoolManager.sol';
import {VolatilityOracle} from '../contracts/hooks/VolatilityOracle.sol';

contract MyScript is Script {
    function run() external {
        uint256 deployerKey = vm.envUint('DEPLOYER_KEY');
        address deployerAddress = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);
        // SETUP
        uint256 CONTROLLER_FEE = 50000;
        PoolManager manager = new PoolManager{salt: 0x0}(CONTROLLER_FEE);
        console2.log('Deployed PoolManager', address(manager));

        VolatilityOracle dynamicFeeHook = new VolatilityOracle{
            salt: 0x4e59b44847b379578588920ca78fbf26c0b4956ca8c62c9e3a9be00000348826
        }(manager);
        console2.log('Deployed VolatilityOracle Hook', address(dynamicFeeHook));

        TestERC20 tokenA = new TestERC20(10**24);
        TestERC20 tokenB = new TestERC20(10**24);
        tokenA.mint(deployerAddress, 10**18);
        tokenB.mint(deployerAddress, 10**18);

        // INITIALIZE POOL
        IPoolManager.PoolKey memory key = IPoolManager.PoolKey(
            Currency.wrap(address(tokenA)),
            Currency.wrap(address(tokenB)),
            type(uint24).max,
            60,
            IHooks(address(dynamicFeeHook))
        );

        uint160 sqrtPriceX96 = 2**96;
        manager.initialize(key, sqrtPriceX96);
        console2.log('Created pool');

        // ADD LIQUIDITY
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
        console2.log('Added liquidity');

        PoolSwapTest swapTest = new PoolSwapTest(manager);
        tokenA.approve(address(swapTest), type(uint256).max);
        tokenB.approve(address(swapTest), type(uint256).max);

        // MAKE SWAPS WITH TIMESTAMP INCREASING
        for (uint256 i = 0; i < 25; i++) {
            swapTest.swap(key, IPoolManager.SwapParams(false, 100, 2**96 * 2), PoolSwapTest.TestSettings(true, true));
            console2.log('Swapped');
            vm.warp(block.timestamp + 100);
        }
        vm.stopBroadcast();
    }
}
