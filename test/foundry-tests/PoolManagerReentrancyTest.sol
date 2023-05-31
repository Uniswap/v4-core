// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {Currency, CurrencyLibrary} from "../../contracts/libraries/CurrencyLibrary.sol";
import {IPoolManager} from "../../contracts/interfaces/IPoolManager.sol";
import {ILockCallback} from "../../contracts/interfaces/callback/ILockCallback.sol";
import {PoolManager} from "../../contracts/PoolManager.sol";
import {Deployers} from "./utils/Deployers.sol";
import {TokenFixture} from "./utils/TokenFixture.sol";

contract TokenLocker is ILockCallback {
    using CurrencyLibrary for Currency;

    function main(IPoolManager manager, Currency currency) external {
        manager.lock(abi.encode(currency));
    }

    function lockAcquired(bytes calldata data) external returns (bytes memory) {
        (Currency currency) = abi.decode(data, (Currency));

        IPoolManager manager = IPoolManager(msg.sender);

        assert(manager.getNonzeroDeltaCount(address(this)) == 0);

        int256 delta = manager.getCurrencyDelta(address(this), currency);
        assert(delta == 0);

        // deposit some tokens
        currency.transfer(address(manager), 1);
        manager.settle(currency);
        assert(manager.getNonzeroDeltaCount(address(this)) == 1);
        delta = manager.getCurrencyDelta(address(this), currency);
        assert(delta == -1);

        // take them back
        manager.take(currency, address(this), 1);
        assert(manager.getNonzeroDeltaCount(address(this)) == 0);
        delta = manager.getCurrencyDelta(address(this), currency);
        assert(delta == 0);

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

    function checker0(uint256) external view {
        assert(manager.locksLength() == 2);
        assert(manager.lockIndex() == 1);
        assert(manager.locksGetter(1).locker == msg.sender);
    }

    function checker1(uint256) external view {
        assert(manager.locksLength() == 3);
        assert(manager.lockIndex() == 2);
        assert(manager.locksGetter(2).locker == msg.sender);
    }

    function lockAcquired(bytes calldata) external returns (bytes memory) {
        SimpleLinearLocker locker0 = new SimpleLinearLocker();
        SimpleLinearLocker locker1 = new SimpleLinearLocker();

        assert(manager.locksLength() == 1);
        assert(manager.lockIndex() == 0);
        assert(manager.locksGetter(0).locker == address(this));
        locker0.main(manager, 0, this.checker0);
        assert(manager.locksLength() == 2);
        assert(manager.lockIndex() == 0);
        locker1.main(manager, 0, this.checker1);
        assert(manager.locksLength() == 3);
        assert(manager.lockIndex() == 0);

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
        locker.main(manager, currency0);
    }

    function checker(uint256 depth) external {
        assertEq(manager.locksLength(), depth + 1);
        assertEq(manager.lockIndex(), depth);
        assertEq(manager.locksGetter(depth).locker, msg.sender);
    }

    function testSimpleLinearLocker() public {
        SimpleLinearLocker locker = new SimpleLinearLocker();
        locker.main(manager, 0, this.checker);
        locker.main(manager, 1, this.checker);
        locker.main(manager, 2, this.checker);
    }

    function testParallelLocker() public {
        ParallelLocker locker = new ParallelLocker(manager);
        locker.main();
    }
}
