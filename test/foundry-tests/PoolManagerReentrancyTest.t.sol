// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {Currency, CurrencyLibrary} from "../../contracts/types/Currency.sol";
import {LockDataLibrary} from "../../contracts/libraries/LockDataLibrary.sol";
import {IPoolManager} from "../../contracts/interfaces/IPoolManager.sol";
import {ILockCallback} from "../../contracts/interfaces/callback/ILockCallback.sol";
import {PoolManager} from "../../contracts/PoolManager.sol";
import {Deployers} from "./utils/Deployers.sol";
import {TokenFixture} from "./utils/TokenFixture.sol";
import {LockSentinel} from "../../contracts/types/LockSentinel.sol";

contract TokenLocker is ILockCallback {
    using CurrencyLibrary for Currency;

    function main(IPoolManager manager, Currency currency, bool reclaim) external {
        manager.lock(abi.encode(currency, reclaim));
    }

    function lockAcquired(bytes calldata data) external returns (bytes memory) {
        (Currency currency, bool reclaim) = abi.decode(data, (Currency, bool));

        IPoolManager manager = IPoolManager(msg.sender);
        LockSentinel sentinel = manager.getLockSentinel();
        assert(sentinel.nonzeroDeltaCount() == 0);

        int256 delta = manager.currencyDelta(address(this), currency);
        assert(delta == 0);

        // deposit some tokens
        currency.transfer(address(manager), 1);
        manager.settle(currency);
        LockSentinel sentinel1 = manager.getLockSentinel();
        assert(sentinel1.nonzeroDeltaCount() == 1);
        delta = manager.currencyDelta(address(this), currency);
        assert(delta == -1);

        // take them back
        if (reclaim) {
            manager.take(currency, address(this), 1);
            LockSentinel sentinel2 = manager.getLockSentinel();
            assert(sentinel2.nonzeroDeltaCount() == 0);
            delta = manager.currencyDelta(address(this), currency);
            assert(delta == 0);
        }

        return "";
    }
}

contract SimpleLinearLocker is ILockCallback {
    function(uint256) external checker;

    function main(IPoolManager manager, uint256 timesToReenter, function(uint256) external checker_) external {
        checker = checker_;
        manager.lock(abi.encode(timesToReenter, 0));
    }

    function lockAcquired(bytes calldata data) external returns (bytes memory) {
        (uint256 timesToReenter, uint256 depth) = abi.decode(data, (uint256, uint256));
        checker(depth);
        if (depth < timesToReenter) {
            IPoolManager manager = IPoolManager(msg.sender);
            manager.lock(abi.encode(timesToReenter, depth + 1));
        }
        return "";
    }
}

contract ParallelLocker is ILockCallback {
    IPoolManager manager;

    constructor(IPoolManager manager_) {
        manager = manager_;
    }

    function main() external {
        manager.lock("");
    }

    function assertionChecker0(uint256) external view {
        LockSentinel sentinel = manager.getLockSentinel();
        assert(sentinel.length() == 2);
        address locker = manager.getLock(1);
        assert(locker == msg.sender);
    }

    function assertionChecker1(uint256 depth) external view {
        LockSentinel sentinel = manager.getLockSentinel();
        assert(sentinel.length() == depth + 2);
        address locker = manager.getLock(depth + 1);
        assert(locker == msg.sender);
    }

    function assertionChecker2(uint256) external view {
        LockSentinel sentinel = manager.getLockSentinel();
        assert(sentinel.length() == 2);
        address locker = manager.getLock(1);
        assert(locker == msg.sender);
    }

    function lockAcquired(bytes calldata) external returns (bytes memory) {
        SimpleLinearLocker locker0 = new SimpleLinearLocker();
        SimpleLinearLocker locker1 = new SimpleLinearLocker();
        SimpleLinearLocker locker2 = new SimpleLinearLocker();

        LockSentinel sentinel = manager.getLockSentinel();
        assert(sentinel.length() == 1);
        address locker = manager.getLock(0);
        assert(locker == address(this));

        locker0.main(manager, 0, this.assertionChecker0);
        LockSentinel sentinel1 = manager.getLockSentinel();
        assert(sentinel1.length() == 1);

        locker1.main(manager, 1, this.assertionChecker1);
        LockSentinel sentinel2 = manager.getLockSentinel();
        assert(sentinel2.length() == 1);

        locker2.main(manager, 0, this.assertionChecker2);
        LockSentinel sentinel3 = manager.getLockSentinel();
        assert(sentinel3.length() == 1);

        return "";
    }
}

contract PoolManagerReentrancyTest is Test, Deployers, TokenFixture {
    PoolManager manager;

    function setUp() public {
        initializeTokens();
        manager = Deployers.createFreshManager();
    }

    function testTokenLocker() public {
        TokenLocker locker = new TokenLocker();
        MockERC20(Currency.unwrap(currency0)).mint(address(locker), 1);
        MockERC20(Currency.unwrap(currency0)).approve(address(locker), 1);
        locker.main(manager, currency0, true);
    }

    function testTokenRevert() public {
        TokenLocker locker = new TokenLocker();
        MockERC20(Currency.unwrap(currency0)).mint(address(locker), 1);
        MockERC20(Currency.unwrap(currency0)).approve(address(locker), 1);
        vm.expectRevert(abi.encodeWithSelector(IPoolManager.CurrencyNotSettled.selector));
        locker.main(manager, currency0, false);
    }

    function assertionChecker(uint256 depth) external {
        LockSentinel sentinel = manager.getLockSentinel();
        assertEq(sentinel.length(), depth + 1);
        address locker = manager.getLock(depth);
        assertEq(locker, msg.sender);
    }

    function testSimpleLinearLocker() public {
        SimpleLinearLocker locker = new SimpleLinearLocker();
        locker.main(manager, 0, this.assertionChecker);
        locker.main(manager, 1, this.assertionChecker);
        locker.main(manager, 2, this.assertionChecker);
    }

    function testParallelLocker() public {
        ParallelLocker locker = new ParallelLocker(manager);
        locker.main();
    }
}
