// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {IHooks} from '../interfaces/IHooks.sol';
import {IERC20Minimal} from '../interfaces/external/IERC20Minimal.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';
import {ITWAMM} from '../interfaces/ITWAMM.sol';
import {Hooks} from '../libraries/Hooks.sol';
import {TickMath} from '../libraries/TickMath.sol';
import {TWAMM} from '../libraries/TWAMM/TWAMM.sol';
import {OrderPool} from '../libraries/TWAMM/OrderPool.sol';
import {BaseHook} from './base/BaseHook.sol';

contract TWAMMHook is BaseHook {
    using TWAMM for TWAMM.State;

    mapping(bytes32 => TWAMM.State) public twammStates;

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

    function getOrderPool(IPoolManager.PoolKey calldata key, bool zeroForOne) external view returns (uint256 sellRateCurrent, uint256 earningsFactorCurrent) {
        OrderPool.State storage orderPool = getTWAMM(key).orderPools[zeroForOne];
        return (orderPool.sellRateCurrent, orderPool.earningsFactorCurrent);
    }

    function beforeInitialize(
        address,
        IPoolManager.PoolKey calldata key,
        uint160
    ) external virtual override poolManagerOnly {
        // Dont need to enforce one-time as each pool can only be initialized once in the manager
        getTWAMM(key).initialize(10000, key);
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

    struct CallbackData {
        address sender;
        IPoolManager.PoolKey key;
        IPoolManager.SwapParams params;
    }

    function executeTWAMMOrders(IPoolManager.PoolKey memory key) public {
        (uint160 sqrtPriceX96, ) = poolManager.getSlot0(key);
        TWAMM.State storage twamm = getTWAMM(key);
        (bool zeroForOne, uint160 sqrtPriceLimitX96) = twamm.executeTWAMMOrders(
            poolManager,
            key,
            TWAMM.PoolParamsOnExecute(sqrtPriceX96, poolManager.getLiquidity(key))
        );

        if (sqrtPriceLimitX96 != 0 && sqrtPriceLimitX96 != sqrtPriceX96) {
            poolManager.lock(abi.encode(key, IPoolManager.SwapParams(zeroForOne, type(int256).max, sqrtPriceLimitX96)));
        }
    }

    function submitLongTermOrder(IPoolManager.PoolKey memory key, TWAMM.LongTermOrderParams memory params)
        external
        returns (bytes32 orderId)
    {
        TWAMM.State storage twamm = getTWAMM(key);
        executeTWAMMOrders(key);
        orderId = twamm.submitLongTermOrder(params);
        IERC20Minimal token = params.zeroForOne ? key.token0 : key.token1;
        token.transferFrom(params.owner, address(this), params.amountIn);
    }

    function modifyLongTermOrder(
        IPoolManager.PoolKey memory key,
        TWAMM.OrderKey memory orderKey,
        int128 amountDelta
    ) external returns (uint256 amountOut0, uint256 amountOut1) {
        executeTWAMMOrders(key);

        (amountOut0, amountOut1) = getTWAMM(key).modifyLongTermOrder(orderKey, amountDelta);

        // IPoolManager.BalanceDelta memory delta = IPoolManager.BalanceDelta({
        //     amount0: -(amountOut0.toInt256()),
        //     amount1: -(amountOut1.toInt256())
        // });
    }

    function claimEarningsOnLongTermOrder(IPoolManager.PoolKey memory key, TWAMM.OrderKey memory orderKey)
        external
        returns (uint256 earningsAmount)
    {
        executeTWAMMOrders(key);

        bool zeroForOne;
        (earningsAmount, zeroForOne) = getTWAMM(key).claimEarnings(orderKey);
        IERC20Minimal buyToken = zeroForOne == 0 ? key.token1 : key.token0;
    }

    function lockAcquired(bytes calldata rawData) external poolManagerOnly returns (bytes memory) {
        (IPoolManager.PoolKey memory key, IPoolManager.SwapParams memory swapParams) = abi.decode(
            rawData,
            (IPoolManager.PoolKey, IPoolManager.SwapParams)
        );

        IPoolManager.BalanceDelta memory delta = poolManager.swap(key, swapParams);

        if (swapParams.zeroForOne) {
            if (delta.amount0 > 0) {
                key.token0.transfer(address(poolManager), uint256(delta.amount0));
                poolManager.settle(key.token0);
            }
            if (delta.amount1 < 0) {
                poolManager.take(key.token1, address(this), uint256(-delta.amount1));
            }
        } else {
            if (delta.amount1 > 0) {
                key.token1.transfer(address(poolManager), uint256(delta.amount1));
                poolManager.settle(key.token1);
            }
            if (delta.amount0 < 0) {
                poolManager.take(key.token0, address(this), uint256(-delta.amount0));
            }
        }
    }

    function getTWAMM(IPoolManager.PoolKey memory key) private view returns (TWAMM.State storage) {
        return twammStates[keccak256(abi.encode(key))];
    }
}
