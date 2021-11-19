// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.2;

import {IERC20Minimal} from '../external/IERC20Minimal.sol';

interface ISettleCallback {
    /// @notice Called on the caller when settle is called, in order for the caller to send payment
    function settleCallback(
        IERC20Minimal token,
        int256 delta,
        bytes calldata data
    ) external;
}
