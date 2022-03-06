// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

import {TWAMM} from '../libraries/TWAMM.sol';

contract TWAMMTest {
    using TWAMM for TWAMM.State;

    TWAMM.State public state;

    function submitLongTermOrder(TWAMM.LongTermOrderParams calldata params) external returns (uint256 orderId) {
        orderId = state.submitLongTermOrder(params);
    }

    function cancelLongTermOrder(uint256 orderId) external {
        state.cancelLongTermOrder(orderId);
    }

    function getOrder(uint256 orderId) external view returns (TWAMM.Order memory) {
        return state.orders[orderId];
    }

    function getOrderPool(uint8 index) external view returns (uint256 sellingRate, uint256 fillerVar) {
        TWAMM.OrderPool storage order = state.orderPools[index];
        sellingRate = order.sellRate;
        fillerVar = 0;
    }

    function getNextId() external view returns (uint256 nextId) {
        return state.nextId;
    }
}
