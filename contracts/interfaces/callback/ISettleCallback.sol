// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20Minimal} from '../external/IERC20Minimal.sol';

interface ISettleCallback {
    function settleCallback(IERC20Minimal token) external;
}
