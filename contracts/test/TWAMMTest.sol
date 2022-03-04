// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;
pragma abicoder v2;

import {TWAMM} from '../libraries/TWAMM.sol';

contract TWAMMTest {
    using TWAMM for TWAMM.State;

    event LongTermOrderSubmitted(uint256 orderId);

    TWAMM.State public longTermOrders;

    function submitLongTermOrder(TWAMM.LongTermOrderParams calldata params) public returns (uint256 orderId) {
        orderId = longTermOrders.submitLongTermOrder(params);
        emit LongTermOrderSubmitted(orderId);
    }

    function getOrder(uint256 orderId) public view returns (TWAMM.Order memory) {
        return longTermOrders.orders[orderId];
    }
}
