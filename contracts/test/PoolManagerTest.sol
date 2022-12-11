// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {IERC20Minimal} from '../interfaces/external/IERC20Minimal.sol';
import {CurrencyDelta} from '../libraries/CurrencyDelta.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';
import {IExecuteCallback} from '../interfaces/callback/IExecuteCallback.sol';

contract PoolManagerTest is IExecuteCallback {
    function lock(IPoolManager manager) external {
        bytes[] memory inputs = new bytes[](0);
        manager.execute('', inputs, '');
    }

    /// @notice Called by the pool manager on `msg.sender` when a lock is acquired
    function executeCallback(CurrencyDelta[] memory deltas, bytes calldata rawData) external returns (bytes memory) {}
}
