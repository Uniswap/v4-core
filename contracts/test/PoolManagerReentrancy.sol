// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {IPoolManager} from '../interfaces/IPoolManager.sol';
import {ILockCallback} from '../interfaces/callback/ILockCallback.sol';

contract PoolManagerReentrancy is ILockCallback {
    event LockAcquired(uint256 count);

    function reenter(IPoolManager poolManager, uint256 count) external {
        poolManager.lock(abi.encode(count));
    }

    function lockAcquired(bytes calldata data) external returns (bytes memory) {
        uint256 count = abi.decode(data, (uint256));
        emit LockAcquired(count);

        assert(IPoolManager(msg.sender).lockedBy(IPoolManager(msg.sender).lockedByLength() - 1) == address(this));
        if (count > 0) this.reenter(IPoolManager(msg.sender), count - 1);
        return '';
    }
}
