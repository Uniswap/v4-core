// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {IERC20Minimal} from '../interfaces/external/IERC20Minimal.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';
import {ILockCallback} from '../interfaces/callback/ILockCallback.sol';

contract PoolManagerReentrancyTest is ILockCallback {
    event LockAcquired(uint256 count);

    function reenter(
        IPoolManager poolManager,
        IERC20Minimal tokenToBorrow,
        uint256 count
    ) external {
        helper(poolManager, tokenToBorrow, count, count);
    }

    function helper(
        IPoolManager poolManager,
        IERC20Minimal tokenToBorrow,
        uint256 total,
        uint256 count
    ) internal {
        // check that it is currently already locked `total-count` times, ...
        assert(poolManager.lockedByLength() == total - count);
        poolManager.lock(abi.encode(tokenToBorrow, total, count));
        // and still has that many locks after this particular lock is released
        assert(poolManager.lockedByLength() == total - count);
    }

    function lockAcquired(bytes calldata data) external returns (bytes memory) {
        (IERC20Minimal tokenToBorrow, uint256 total, uint256 count) = abi.decode(
            data,
            (IERC20Minimal, uint256, uint256)
        );
        emit LockAcquired(count);

        uint256 id = total - count;

        IPoolManager poolManager = IPoolManager(msg.sender);

        assert(poolManager.lockedBy(id) == address(this));
        assert(poolManager.lockedByLength() == id + 1);

        // tokens touched length is 0 when we enter
        assert(poolManager.getTokensTouchedLength(id) == 0);

        (uint8 slot, int248 delta) = poolManager.getTokenDelta(id, tokenToBorrow);
        assert(slot == 0 && delta == 0);

        // take some
        poolManager.take(tokenToBorrow, address(this), 1);
        assert(poolManager.getTokensTouchedLength(id) == 1);
        (slot, delta) = poolManager.getTokenDelta(id, tokenToBorrow);
        assert(slot == 0 && delta == 1);

        // then pay it back
        tokenToBorrow.transfer(address(poolManager), 1);
        poolManager.settle(tokenToBorrow);
        assert(poolManager.getTokensTouchedLength(id) == 1);
        (slot, delta) = poolManager.getTokenDelta(id, tokenToBorrow);
        assert(slot == 0 && delta == 0);

        if (count > 0) helper(IPoolManager(msg.sender), tokenToBorrow, total, count - 1);

        return '';
    }
}
