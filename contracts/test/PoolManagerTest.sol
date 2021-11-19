// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.10;

import {IERC20Minimal} from '../interfaces/external/IERC20Minimal.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';
import {IPoolManagerUser} from '../interfaces/callback/IPoolManagerUser.sol';

contract PoolManagerTest is IPoolManagerUser {
    function lock(IPoolManager manager) external {
        manager.lock('');
    }

    /// @notice Called by the pool manager on `msg.sender` when a lock is acquired
    function lockAcquired(bytes calldata) external override returns (bool) {
        return true;
    }

    /// @notice Called on the caller when settle is called, in order for the caller to send payment
    function settleCallback(IERC20Minimal, int256) external {
        revert('cannot pay');
    }
}
