// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILockCallback {
    /// @notice Called by the pool manager on `msg.sender` when a lock is acquired
    /// @param lockCaller The address that originally locked the PoolManager
    /// @param data The data that was passed to the call to lock
    /// @return Any data that you want to be returned from the lock call
    function lockAcquired(address lockCaller, bytes calldata data) external returns (bytes memory);
}
