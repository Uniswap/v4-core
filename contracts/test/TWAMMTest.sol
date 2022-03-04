// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;
pragma abicoder v2;

import {TWAMM} from '../libraries/TWAMM.sol';

contract TWAMMTest {
    using TWAMM for TWAMM.LongTermOrders;

    event LongTermOrderSubmitted(bytes32 orderId);

    TWAMM.LongTermOrders public longTermOrders;

    function submitLongTermOrder(TWAMM.LongTermOrderParams calldata params) public returns (bytes32 orderId) {
        orderId = longTermOrders.submitLongTermOrder(params);
        emit LongTermOrderSubmitted(orderId);
    }

    function getOrder(bool zeroForOne, bytes32 orderId) public view returns (TWAMM.Order memory) {
        uint8 tokenIndex = zeroForOne ? 0 : 1;
        return longTermOrders.orderPools[tokenIndex].orders[orderId];
    }
}
