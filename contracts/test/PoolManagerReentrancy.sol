// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {IPoolManager} from '../interfaces/IPoolManager.sol';
import {ILockCallback} from '../interfaces/callback/ILockCallback.sol';

contract PoolManagerReentrancy is ILockCallback {
    event LockAcquired(uint256 count);

    function reenter(IPoolManager poolManager, uint256 count) external {
        helper(poolManager, count, count);
    }

    function helper(
        IPoolManager poolManager,
        uint256 total,
        uint256 count
    ) internal {
        poolManager.lock(abi.encode(total, count));
    }

    function lockAcquired(bytes calldata data) external returns (bytes memory) {
        (uint256 total, uint256 count) = abi.decode(data, (uint256, uint256));
        emit LockAcquired(count);

        uint256 id = total - count;

        IPoolManager poolManager = IPoolManager(msg.sender);

        assert(poolManager.lockedBy(id) == address(this));
        assert(poolManager.lockedByLength() == id + 1);

        if (count > 0) helper(IPoolManager(msg.sender), total, count - 1);

        return '';
    }
}
