// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {Currency, CurrencyLibrary} from '../libraries/CurrencyLibrary.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';
import {ILockCallback} from '../interfaces/callback/ILockCallback.sol';

contract PoolManagerReentrancyTest is ILockCallback {
    using CurrencyLibrary for Currency;

    event LockAcquired(uint256 count);

    function reenter(
        IPoolManager poolManager,
        Currency currencyToBorrow,
        uint256 count
    ) external {
        helper(poolManager, currencyToBorrow, count, count);
    }

    function helper(
        IPoolManager poolManager,
        Currency currencyToBorrow,
        uint256 total,
        uint256 count
    ) internal {
        // check that it is currently already locked `total-count` times, ...
        assert(poolManager.lockedByLength() == total - count);
        poolManager.lock(abi.encode(currencyToBorrow, total, count));
        // and still has that many locks after this particular lock is released
        assert(poolManager.lockedByLength() == total - count);
    }

    function lockAcquired(bytes calldata data) external returns (bytes memory) {
        (Currency currencyToBorrow, uint256 total, uint256 count) = abi.decode(data, (Currency, uint256, uint256));
        emit LockAcquired(count);

        uint256 id = total - count;

        IPoolManager poolManager = IPoolManager(msg.sender);

        assert(poolManager.lockedBy(id) == address(this));
        assert(poolManager.lockedByLength() == id + 1);

        // currencies touched length is 0 when we enter
        assert(poolManager.getCurrenciesTouchedLength(id) == 0);

        (uint8 index, int248 delta) = poolManager.getCurrencyDelta(id, currencyToBorrow);
        assert(index == 0 && delta == 0);

        // take some
        poolManager.take(currencyToBorrow, address(this), 1);
        assert(poolManager.getCurrenciesTouchedLength(id) == 1);
        (index, delta) = poolManager.getCurrencyDelta(id, currencyToBorrow);
        assert(index == 0 && delta == 1);

        // then pay it back
        currencyToBorrow.transfer(address(poolManager), 1);
        poolManager.settle(currencyToBorrow);
        assert(poolManager.getCurrenciesTouchedLength(id) == 1);
        (index, delta) = poolManager.getCurrencyDelta(id, currencyToBorrow);
        assert(index == 0 && delta == 0);

        if (count > 0) helper(IPoolManager(msg.sender), currencyToBorrow, total, count - 1);

        return '';
    }
}
