// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {IERC20Minimal} from "../interfaces/external/IERC20Minimal.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {ILockCallback} from "../interfaces/callback/ILockCallback.sol";

contract PoolManagerTest is ILockCallback {
    function lock(IPoolManager manager) external {
        manager.lock("");
    }

    /// @notice Called by the pool manager on `msg.sender` when a lock is acquired
    function lockAcquired(bytes calldata) external override returns (bytes memory) {}
}
