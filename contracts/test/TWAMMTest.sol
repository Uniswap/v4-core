// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {TWAMM} from '../libraries/TWAMM/TWAMM.sol';
import {TwammMath} from '../libraries/TWAMM/TwammMath.sol';
import {Pool} from '../libraries/Pool.sol';
import {OrderPool} from '../libraries/TWAMM/OrderPool.sol';
import {Tick} from '../libraries/Tick.sol';
import {ABDKMathQuad} from 'abdk-libraries-solidity/ABDKMathQuad.sol';
import {FixedPoint96} from '../libraries/FixedPoint96.sol';

contract TWAMMTest {
    using Pool for Pool.State;
    using TWAMM for TWAMM.State;
    using ABDKMathQuad for *;

    Pool.State private pool;

    struct PoolParamsOnExecute {
        uint160 sqrtPriceX96;
        uint128 liquidity;
        uint24 fee;
        int24 tickSpacing;
    }

    struct OrderPoolParamsOnExecute {
        uint256 sellRateCurrent0;
        uint256 sellRateCurrent1;
    }

    function initialize(uint256 orderInterval) external {
        pool.initialize(uint32(block.timestamp), 1 << 96, orderInterval);
    }

    function submitLongTermOrder(TWAMM.LongTermOrderParams calldata params) external returns (bytes32 orderId) {
        orderId = pool.twamm.submitLongTermOrder(params);
    }

    function modifyLongTermOrder(TWAMM.OrderKey calldata orderKey, int128 amountDelta)
        external
        returns (uint256 amountOut0, uint256 amountOut1)
    {
        (amountOut0, amountOut1) = pool.twamm.modifyLongTermOrder(orderKey, amountDelta);
    }

    function claimEarnings(TWAMM.OrderKey calldata orderKey)
        external
        returns (
            uint256 earningsAmount,
            uint8 sellTokenIndex,
            uint256 unclaimedEarningsAmount
        )
    {
        (earningsAmount, sellTokenIndex) = pool.twamm.claimEarnings(orderKey);
        // unclaimedEarningsFactor is a fixed point
        uint256 sellRateCurrent = pool.twamm._getOrder(orderKey).sellRate;
        unclaimedEarningsAmount =
            (pool.twamm._getOrder(orderKey).unclaimedEarningsFactor * sellRateCurrent) >>
            FixedPoint96.RESOLUTION;
    }

    function executeTWAMMOrders(PoolParamsOnExecute memory params) external {
        pool.slot0.sqrtPriceX96 = params.sqrtPriceX96;
        pool.liquidity = params.liquidity;

        pool.executeTwammOrders(Pool.ExecuteTWAMMParams(params.fee, params.tickSpacing));
    }

    function calculateExecutionUpdates(
        uint256 secondsElapsed,
        PoolParamsOnExecute memory poolParams,
        OrderPoolParamsOnExecute memory orderPoolParams
    )
        external
        returns (
            uint160 sqrtPriceX96,
            uint256 earningsPool0,
            uint256 earningsPool1
        )
    {
        (sqrtPriceX96, earningsPool0, earningsPool1) = TwammMath.calculateExecutionUpdates(
            TwammMath.ExecutionUpdateParams(
                secondsElapsed,
                poolParams.sqrtPriceX96,
                poolParams.liquidity,
                orderPoolParams.sellRateCurrent0,
                orderPoolParams.sellRateCurrent1
            )
        );
    }

    function calculateTimeBetweenTicks(
        uint256 liquidity,
        uint160 sqrtPriceStartX96,
        uint160 sqrtPriceEndX96,
        uint256 sellRate0,
        uint256 sellRate1
    ) external returns (uint256) {
        return TwammMath.calculateTimeBetweenTicks(liquidity, sqrtPriceStartX96, sqrtPriceEndX96, sellRate0, sellRate1);
    }

    function getOrder(TWAMM.OrderKey calldata orderKey) external view returns (TWAMM.Order memory) {
        return pool.twamm._getOrder(orderKey);
    }

    function getOrderPool(uint8 index) external view returns (uint256 sellRate, uint256 earningsFactor) {
        OrderPool.State storage orderPool = pool.twamm.orderPools[index];
        sellRate = orderPool.sellRateCurrent;
        earningsFactor = orderPool.earningsFactorCurrent;
    }

    function getOrderPoolSellRateEndingPerInterval(uint8 sellTokenIndex, uint256 timestamp)
        external
        view
        returns (uint256 sellRate)
    {
        return pool.twamm.orderPools[sellTokenIndex].sellRateEndingAtInterval[timestamp];
    }

    function getOrderPoolEarningsFactorAtInterval(uint8 sellTokenIndex, uint256 timestamp)
        external
        view
        returns (uint256 sellRate)
    {
        return pool.twamm.orderPools[sellTokenIndex].earningsFactorAtInterval[timestamp];
    }

    function getState() external view returns (uint256 expirationInterval, uint256 lastVirtualOrderTimestamp) {
        expirationInterval = pool.twamm.expirationInterval;
        lastVirtualOrderTimestamp = pool.twamm.lastVirtualOrderTimestamp;
    }
}
