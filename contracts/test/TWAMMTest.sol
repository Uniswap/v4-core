// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {TWAMM} from '../libraries/TWAMM/TWAMM.sol';
import {TwammMath} from '../libraries/TWAMM/TwammMath.sol';
import {OrderPool} from '../libraries/TWAMM/OrderPool.sol';
import {Tick} from '../libraries/Tick.sol';
import {ABDKMathQuad} from 'abdk-libraries-solidity/ABDKMathQuad.sol';
import {FixedPoint96} from '../libraries/FixedPoint96.sol';
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

    function submitLongTermOrder(TWAMM.LongTermOrderParams calldata params) external returns (bytes32 orderId) {
        orderId = twamm.submitLongTermOrder(params);
    }

    function modifyLongTermOrder(TWAMM.OrderKey calldata orderKey, int128 amountDelta)
        external
        returns (uint256 amountOut0, uint256 amountOut1)
    {
        (amountOut0, amountOut1) = twamm.modifyLongTermOrder(orderKey, amountDelta);
    }

    function claimEarnings(TWAMM.OrderKey calldata orderKey)
        external
        returns (
            uint256 earningsAmount,
            uint8 sellTokenIndex,
            uint256 unclaimedEarningsAmount
        )
    {
        (earningsAmount, sellTokenIndex) = twamm.claimEarnings(orderKey);
        // unclaimedEarningsFactor is a fixed point
        uint256 sellRateCurrent = twamm._getOrder(orderKey).sellRate;
        unclaimedEarningsAmount =
            (twamm._getOrder(orderKey).unclaimedEarningsFactor * sellRateCurrent) >>
            FixedPoint96.RESOLUTION;
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
            uint256 earningsPool1,
            uint256 earningsAmount0,
            uint256 earningsAmount1
        )
    {
        uint160 finalSqrtPriceX96 = TwammMath.getNewSqrtPriceX96(
            secondsElapsed,
            poolParams.sqrtPriceX96,
            poolParams.liquidity,
            orderPoolParams
        );
        (earningsPool0, earningsPool1) = TwammMath.calculateEarningsUpdates(
            secondsElapsed,
            poolParams.sqrtPriceX96,
            finalSqrtPriceX96,
            poolParams.liquidity,
            orderPoolParams
        );

        earningsAmount0 = (earningsPool0 * orderPoolParams.sellRateCurrent0) >> FixedPoint96.RESOLUTION;
        earningsAmount1 = (earningsPool1 * orderPoolParams.sellRateCurrent1) >> FixedPoint96.RESOLUTION;

        return (finalSqrtPriceX96, earningsPool0, earningsPool1, earningsAmount0, earningsAmount1);
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
        return twamm._getOrder(orderKey);
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

    function getState() external view returns (uint256 expirationInterval, uint256 lastVirtualOrderTimestamp) {
        expirationInterval = twamm.expirationInterval;
        lastVirtualOrderTimestamp = twamm.lastVirtualOrderTimestamp;
    }
}
