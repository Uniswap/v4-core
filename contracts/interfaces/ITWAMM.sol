// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {TWAMM} from '../libraries/TWAMM/TWAMM.sol';

interface ITWAMM {
    function submitLongTermOrder(TWAMM.LongTermOrderParams calldata params) external returns (uint256 orderId);

    function cancelLongTermOrder(uint256 orderId) external;
}
