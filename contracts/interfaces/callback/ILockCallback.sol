// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface ILockCallback {
    /// @notice Called by the pool manager on `msg.sender` when a lock is acquired
    function lockAcquired() external;
}
