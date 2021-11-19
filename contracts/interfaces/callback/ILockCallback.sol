// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.2;

interface ILockCallback {
    /// @notice Called by the pool manager on `msg.sender` when a lock is acquired
    /// todo: this should be able to return data that is passed through to the lock caller
    function lockAcquired(bytes calldata data) external returns (bytes memory);
}
