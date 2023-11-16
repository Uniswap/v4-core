// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Currency, CurrencyLibrary} from "../src/types/Currency.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {ILockCallback} from "../src/interfaces/callback/ILockCallback.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {Deployers} from "./utils/Deployers.sol";

contract TokenLocker is ILockCallback {
    using CurrencyLibrary for Currency;

    function main(IPoolManager manager, Currency currency, bool reclaim) external {
        manager.lock(abi.encode(currency, reclaim));
    }

    function lockAcquired(bytes calldata data) external returns (bytes memory) {
        (Currency currency, bool reclaim) = abi.decode(data, (Currency, bool));

        IPoolManager manager = IPoolManager(msg.sender);
        uint256 count = manager.getLockNonzeroDeltaCount();
        assert(count == 0);

        int256 delta = manager.currencyDelta(address(this), currency);
        assert(delta == 0);

        // deposit some tokens
        currency.transfer(address(manager), 1);
        manager.settle(currency);
        count = manager.getLockNonzeroDeltaCount();
        assert(count == 1);
        delta = manager.currencyDelta(address(this), currency);
        assert(delta == -1);

        // take them back
        if (reclaim) {
            manager.take(currency, address(this), 1);
            count = manager.getLockNonzeroDeltaCount();
            assert(count == 0);
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
    // We define an INDEX_OFFSET at 1 since the first locker is placed at index 1.
    // The 0th index is used for storing the length.
    uint256 constant INDEX_OFFSET = 1;
    IPoolManager manager;

    constructor(IPoolManager manager_) {
        manager = manager_;
    }

    function main() external {
        manager.lock("");
    }

    function assertionChecker0(uint256) external view {
        uint256 length = manager.getLockLength();
        assert(length == 2);
        address locker = manager.getLock(INDEX_OFFSET + 1);
        assert(locker == msg.sender);
    }

    function assertionChecker1(uint256 depth) external view {
        uint256 length = manager.getLockLength();
        assert(length == depth + 2);
        address locker = manager.getLock(INDEX_OFFSET + depth + 1);
        assert(locker == msg.sender);
    }

    function assertionChecker2(uint256) external view {
        uint256 length = manager.getLockLength();
        assert(length == 2);
        address locker = manager.getLock(INDEX_OFFSET + 1);
        assert(locker == msg.sender);
    }

    function lockAcquired(bytes calldata) external returns (bytes memory) {
        SimpleLinearLocker locker0 = new SimpleLinearLocker();
        SimpleLinearLocker locker1 = new SimpleLinearLocker();
        SimpleLinearLocker locker2 = new SimpleLinearLocker();

        uint256 length = manager.getLockLength();
        assert(length == 1);
        address locker = manager.getLock(INDEX_OFFSET + 0);
        assert(locker == address(this));

        locker0.main(manager, 0, this.assertionChecker0);
        uint256 length1 = manager.getLockLength();
        assert(length1 == 1);

        locker1.main(manager, 1, this.assertionChecker1);
        uint256 length2 = manager.getLockLength();
        assert(length2 == 1);

        locker2.main(manager, 0, this.assertionChecker2);
        uint256 length3 = manager.getLockLength();
        assert(length3 == 1);

        return "";
    }
}

contract PoolManagerReentrancyTest is Test, Deployers {
    uint256 constant INDEX_OFFSET = 1;

    function setUp() public {
        initializeManagerRoutersAndPoolsWithLiq(IHooks(address(0)));
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
        uint256 length = manager.getLockLength();
        assertEq(length, depth + 1);
        address locker = manager.getLock(INDEX_OFFSET + depth);
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
