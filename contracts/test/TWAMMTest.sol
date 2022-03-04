// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;
pragma abicoder v2;

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

    function getOrderPool(uint8 index) external view returns (TWAMM.OrderPool memory) {
        return state.orderPools[index];
    }

    function getNextId() external view returns (uint256 nextId) {
        return state.nextId;
    }
}
