// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {Currency, CurrencyLibrary} from "../libraries/CurrencyLibrary.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {ILockCallback} from "../interfaces/callback/ILockCallback.sol";

contract PoolManagerReentrancyTest is ILockCallback {
    using CurrencyLibrary for Currency;

    event LockAcquired(uint256 count);

    function reenter(IPoolManager poolManager, Currency currencyToBorrow, uint256 count) external {
        helper(poolManager, currencyToBorrow, count, count);
    }

    function helper(IPoolManager poolManager, Currency currencyToBorrow, uint256 total, uint256 count) internal {
        poolManager.lock(abi.encode(currencyToBorrow, total, count));
    }

    function lockAcquired(bytes calldata data) external returns (bytes memory) {
        (Currency currencyToBorrow, uint256 total, uint256 count) = abi.decode(data, (Currency, uint256, uint256));
        emit LockAcquired(count);

        IPoolManager poolManager = IPoolManager(msg.sender);

        // assert(poolManager.lockedBy(id) == address(this));
        // assert(poolManager.lockedByLength() == id + 1);

        assert(poolManager.getNonzeroDeltaCount(address(this)) == 0);

        int256 delta = poolManager.getCurrencyDelta(address(this), currencyToBorrow);
        assert(delta == 0);

        // take some
        poolManager.take(currencyToBorrow, address(this), 1);
        assert(poolManager.getNonzeroDeltaCount(address(this)) == 1);
        delta = poolManager.getCurrencyDelta(address(this), currencyToBorrow);
        assert(delta == 1);

        // then pay it back
        currencyToBorrow.transfer(address(poolManager), 1);
        poolManager.settle(currencyToBorrow);
        assert(poolManager.getNonzeroDeltaCount(address(this)) == 0);
        delta = poolManager.getCurrencyDelta(address(this), currencyToBorrow);
        assert(delta == 0);

        if (count > 0) helper(IPoolManager(msg.sender), currencyToBorrow, total, count - 1);

        return "";
    }
}
