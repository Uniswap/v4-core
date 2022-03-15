// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

import {TWAMM} from '../libraries/TWAMM.sol';
import {Tick} from '../libraries/Tick.sol';

contract TWAMMTest {
    using TWAMM for TWAMM.State;

    TWAMM.State public twamm;
    mapping(int24 => Tick.Info) mockTicks;

    event ClaimEarnings(uint256 earningsAmount, uint256 unclaimedEarnings);

    function initialize(uint256 orderInterval) external {
        twamm.initialize(orderInterval);
    }

    function submitLongTermOrder(TWAMM.LongTermOrderParams calldata params) external returns (uint256 orderId) {
        orderId = twamm.submitLongTermOrder(params);
    }

    function cancelLongTermOrder(uint256 orderId) external {
        twamm.cancelLongTermOrder(orderId);
    }

    function calculateTWAMMExecutionUpdates(
        uint256 startingTimestamp,
        uint256 endingTimeStamp,
        TWAMM.PoolParamsOnExecute memory poolParams,
        TWAMM.OrderPoolParamsOnExecute memory orderPoolParams
    )
        external
        returns (
            uint160 sqrtPriceX96,
            uint256 earningsFactorPool0,
            uint256 earningsFactorPool1
        )
    {
        TWAMM.calculateTWAMMExecutionUpdates(
            startingTimestamp,
            endingTimeStamp,
            poolParams,
            orderPoolParams,
            mockTicks
        );
    }

    function getOrder(uint256 orderId) external view returns (TWAMM.Order memory) {
        return twamm.orders[orderId];
    }

    function getOrderPool(uint8 index) external view returns (uint256 sellRate, uint256 earningsFactor) {
        TWAMM.OrderPool storage order = twamm.orderPools[index];
        sellRate = order.sellRate;
        earningsFactor = order.earningsFactor;
    }

    function getOrderPoolSellRateEndingPerInterval(uint8 sellTokenIndex, uint256 timestamp)
        external
        view
        returns (uint256 sellRate)
    {
        return twamm.orderPools[sellTokenIndex].sellRateEndingAtInterval[timestamp];
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

    function claimEarnings(uint256 orderId, TWAMM.PoolParamsOnExecute memory params)
        external
        returns (uint256 earningsAmount, uint8 sellTokenIndex)
    {
        (earningsAmount, sellTokenIndex) = twamm.claimEarnings(orderId, params, mockTicks);
        uint256 unclaimed = twamm.orders[orderId].unclaimedEarningsFactor;
        emit ClaimEarnings(earningsAmount, unclaimed);
    }
}
