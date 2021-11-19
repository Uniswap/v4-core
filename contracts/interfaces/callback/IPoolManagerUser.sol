// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.2;

import {IERC20Minimal} from '../external/IERC20Minimal.sol';

/// @notice Capable of acquiring locks and interacting with the IPoolManager
interface IPoolManagerUser {
    /// @notice Called by the pool manager on `msg.sender` when a lock is acquired
    function lockAcquired(bytes calldata data) external returns (bool);

    /// @notice Called on the caller when settle is called, in order for the caller to send payment
    function settleCallback(IERC20Minimal token, int256 delta) external;
}
