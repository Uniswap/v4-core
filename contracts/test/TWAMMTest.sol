// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {TWAMM} from '../libraries/TWAMM/TWAMM.sol';
import {TwammMath} from '../libraries/TWAMM/TwammMath.sol';
import {OrderPool} from '../libraries/TWAMM/OrderPool.sol';
import {Tick} from '../libraries/Tick.sol';
import {ABDKMathQuad} from 'abdk-libraries-solidity/ABDKMathQuad.sol';
import 'hardhat/console.sol';

contract TWAMMTest {
    using TWAMM for TWAMM.State;
    using ABDKMathQuad for *;

    TWAMM.State public twamm;
    mapping(int24 => Tick.Info) mockTicks;
    mapping(int16 => uint256) mockTickBitmap;

    function initialize(uint256 orderInterval) external {
        twamm.initialize(orderInterval);
    }

    function submitLongTermOrder(TWAMM.LongTermOrderParams calldata params) external returns (uint256 orderId) {
        orderId = twamm.submitLongTermOrder(params);
    }

    function cancelLongTermOrder(uint256 orderId) external returns (uint256 amountOut0, uint256 amountOut1) {
        (amountOut0, amountOut1) = twamm.cancelLongTermOrder(orderId);
    }

    function claimEarnings(uint256 orderId, TWAMM.PoolParamsOnExecute memory params)
        external
        returns (
            uint256 earningsAmount,
            uint8 sellTokenIndex,
            uint256 unclaimedEarnings
        )
    {
        twamm.executeTWAMMOrders(params, mockTicks, mockTickBitmap);
        (earningsAmount, sellTokenIndex) = twamm.claimEarnings(orderId);
        unclaimedEarnings = twamm.orders[orderId].unclaimedEarningsFactor;
    }

    function executeTWAMMOrders(TWAMM.PoolParamsOnExecute memory poolParams) external {
        twamm.executeTWAMMOrders(poolParams, mockTicks, mockTickBitmap);
    }

    function calculateExecutionUpdates(
        uint256 secondsElapsed,
        TWAMM.PoolParamsOnExecute memory poolParams,
        TWAMM.OrderPoolParamsOnExecute memory orderPoolParams
    )
        external
        returns (
            uint160 sqrtPriceX96,
            uint256 earningsPool0,
            uint256 earningsPool1
        )
    {
        (sqrtPriceX96, earningsPool0, earningsPool1) = TwammMath.calculateExecutionUpdates(
            secondsElapsed,
            poolParams,
            orderPoolParams,
            mockTicks
        );
    }

    function calculateTimeBetweenTicks(
        uint256 liquidity,
        uint256 sqrtPriceStartX96,
        uint256 sqrtPriceEndX96,
        uint256 sqrtSellRate,
        uint256 sqrtSellRatioX96
    ) external view returns (uint256) {
        bytes16 result = TwammMath.calculateTimeBetweenTicks(
            liquidity.fromUInt(),
            sqrtPriceStartX96.fromUInt(),
            sqrtPriceEndX96.fromUInt(),
            sqrtSellRate.fromUInt(),
            sqrtSellRatioX96.fromUInt()
        );
        return result.toUInt();
    }

    function getOrder(uint256 orderId) external view returns (TWAMM.Order memory) {
        return twamm.orders[orderId];
    }

    function getOrderPool(uint8 index) external view returns (uint256 sellRate, uint256 earningsFactor) {
        OrderPool.State storage orderPool = twamm.orderPools[index];
        sellRate = orderPool.sellRateCurrent;
        earningsFactor = orderPool.earningsFactorCurrent;
    }

    function getOrderPoolSellRateEndingPerInterval(uint8 sellTokenIndex, uint256 timestamp)
        external
        view
        returns (uint256 sellRate)
    {
        return twamm.orderPools[sellTokenIndex].sellRateEndingAtInterval[timestamp];
    }

    function getOrderPoolEarningsFactorAtInterval(uint8 sellTokenIndex, uint256 timestamp)
        external
        view
        returns (uint256 sellRate)
    {
        return twamm.orderPools[sellTokenIndex].earningsFactorAtInterval[timestamp];
    }

    function getState()
        external
        view
        returns (
            uint256 expirationInterval,
            uint256 lastVirtualOrderTimestamp,
            uint256 nextId
        )
    {
        expirationInterval = twamm.expirationInterval;
        lastVirtualOrderTimestamp = twamm.lastVirtualOrderTimestamp;
        nextId = twamm.nextId;
    }

    function getNextId() external view returns (uint256 nextId) {
        return twamm.nextId;
    }
}
