// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

interface ILockCallback {
    /// @notice Called by the pool manager on `msg.sender` when a lock is acquired
    /// @param id The id of the lock that was acquired
    /// @param data The data that was passed to the call to lock
    /// @return Any data that you want to be returned from the lock call
    function lockAcquired(uint256 id, bytes calldata data) external returns (bytes memory);
}
