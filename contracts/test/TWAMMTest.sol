// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

import {TWAMM} from '../libraries/TWAMM.sol';
import {OrderPool} from '../libraries/TWAMM/OrderPool.sol';
import {Tick} from '../libraries/Tick.sol';

contract TWAMMTest {
    using TWAMM for TWAMM.State;

    TWAMM.State public twamm;
    mapping(int24 => Tick.Info) mockTicks;

    function initialize(uint256 orderInterval) external {
        twamm.initialize(orderInterval);
    }

    function submitLongTermOrder(TWAMM.LongTermOrderParams calldata params) external returns (uint256 orderId) {
        orderId = twamm.submitLongTermOrder(params);
    }

    function cancelLongTermOrder(uint256 orderId) external {
        twamm.cancelLongTermOrder(orderId);
    }

    function executeTWAMMOrders(TWAMM.PoolParamsOnExecute memory poolParams) external {
        twamm.executeTWAMMOrders(poolParams, mockTicks);
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
        (sqrtPriceX96, earningsPool0, earningsPool1) = TWAMM.calculateExecutionUpdates(
            secondsElapsed,
            poolParams,
            orderPoolParams,
            mockTicks
        );
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
