// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC20Minimal} from "../interfaces/external/IERC20Minimal.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {ILockCallback} from "../interfaces/callback/ILockCallback.sol";

contract PoolLockTest is ILockCallback {
    event LockAcquired(uint256 id);

    IPoolManager manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    function lock() external {
        manager.lock("");
    }

    /// @notice Called by the pool manager on `msg.sender` when a lock is acquired
    function lockAcquired(uint256 id, bytes calldata) external override returns (bytes memory) {
        emit LockAcquired(id);
        return "";
    }
}
