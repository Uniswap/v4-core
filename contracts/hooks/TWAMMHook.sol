// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {IHooks} from '../interfaces/IHooks.sol';
import {IERC20Minimal} from '../interfaces/external/IERC20Minimal.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';
import {ITWAMM} from '../interfaces/ITWAMM.sol';
import {Hooks} from '../libraries/Hooks.sol';
import {TickMath} from '../libraries/TickMath.sol';
import {TWAMM} from '../libraries/TWAMM/TWAMM.sol';
import {BaseHook} from './base/BaseHook.sol';

contract TWAMMHook is BaseHook {
    using TWAMM for TWAMM.State;

    TWAMM.State public twamm;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        Hooks.validateHookAddress(
            this,
            Hooks.Calls({
                beforeInitialize: true,
                afterInitialize: false,
                beforeModifyPosition: true,
                afterModifyPosition: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
            })
        );
    }

    function beforeInitialize(
        address,
        IPoolManager.PoolKey calldata key,
        uint160
    ) external virtual override poolManagerOnly {
        twamm.initialize(10000, key);
    }

    function beforeModifyPosition(
        address,
        IPoolManager.PoolKey calldata key,
        IPoolManager.ModifyPositionParams calldata
    ) external override poolManagerOnly {
        executeTWAMMOrders(key);
    }

    function beforeSwap(
        address,
        IPoolManager.PoolKey calldata key,
        IPoolManager.SwapParams calldata
    ) external override poolManagerOnly {
        executeTWAMMOrders(key);
    }

    function executeTWAMMOrders(IPoolManager.PoolKey memory key) public {
        (uint160 sqrtPriceX96, ) = poolManager.getSlot0(key);
        (bool zeroForOne, uint160 sqrtPriceLimitX96) = twamm.executeTWAMMOrders(
            poolManager,
            TWAMM.PoolParamsOnExecute(sqrtPriceX96, poolManager.getLiquidity(key))
        );

        if (sqrtPriceLimitX96 != 0 && sqrtPriceLimitX96 != sqrtPriceX96) {
            IPoolManager.BalanceDelta memory delta = poolManager.swap(
                key,
                IPoolManager.SwapParams(zeroForOne, type(int256).max, sqrtPriceLimitX96)
            );
        }
    }

    function submitLongTermOrder(TWAMM.LongTermOrderParams memory params) external returns (bytes32 orderId) {
        executeTWAMMOrders(twamm.poolKey);
        orderId = twamm.submitLongTermOrder(params);
        IERC20Minimal token = params.zeroForOne ? twamm.poolKey.token0 : twamm.poolKey.token1;
    }

    function modifyLongTermOrder(TWAMM.OrderKey memory orderKey, int128 amountDelta)
        external
        returns (uint256 amountOut0, uint256 amountOut1)
    {
        executeTWAMMOrders(twamm.poolKey);

        (amountOut0, amountOut1) = twamm.modifyLongTermOrder(orderKey, amountDelta);

        // IPoolManager.BalanceDelta memory delta = IPoolManager.BalanceDelta({
        //     amount0: -(amountOut0.toInt256()),
        //     amount1: -(amountOut1.toInt256())
        // });
    }

    function claimEarningsOnLongTermOrder(TWAMM.OrderKey memory orderKey) external returns (uint256 earningsAmount) {
        executeTWAMMOrders(twamm.poolKey);

        uint8 sellTokenIndex;
        (earningsAmount, sellTokenIndex) = twamm.claimEarnings(orderKey);
        IERC20Minimal buyToken = sellTokenIndex == 0 ? twamm.poolKey.token1 : twamm.poolKey.token0;
    }
}
