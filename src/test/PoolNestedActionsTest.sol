// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {ILockCallback} from "../interfaces/callback/ILockCallback.sol";
import {PoolTestBase} from "./PoolTestBase.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {Constants} from "../../test/utils/Constants.sol";
import {Test} from "forge-std/Test.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {Currency} from "../types/Currency.sol";

enum Action {
    NESTED_SELF_LOCK,
    NESTED_EXECUTOR_LOCK,
    SWAP_AND_SETTLE,
    DONATE_AND_SETTLE,
    ADD_LIQ_AND_SETTLE,
    REMOVE_LIQ_AND_SETTLE
}

contract PoolNestedActionsTest is Test, ILockCallback {
    IPoolManager manager;
    NestedActionExecutor public executor;
    address user;

    constructor(IPoolManager _manager) {
        manager = _manager;
        user = msg.sender;
        executor = new NestedActionExecutor(manager, user);
    }

    function lock(bytes calldata data) external {
        manager.lock(data);
    }

    /// @notice Called by the pool manager on `msg.sender` when a lock is acquired
    function lockAcquired(bytes calldata data) external override returns (bytes memory) {
        Action[] memory actions = abi.decode(data, (Action[]));
        if (actions.length == 1 && actions[0] == Action.NESTED_SELF_LOCK) {
            _nestedLock();
        } else {
            executor.execute(actions);
        }
        return "";
    }

    function _nestedLock() internal {
        address locker = manager.getLocker();
        assertEq(locker, address(this));

        vm.expectRevert(abi.encodeWithSelector(IPoolManager.AlreadyLocked.selector));
        manager.lock("");

        locker = manager.getLocker();
        assertEq(locker, address(this));
    }
}

contract NestedActionExecutor is Test, PoolTestBase {
    PoolKey internal key;
    address user;

    error KeyNotSet();

    IPoolManager.ModifyLiquidityParams internal ADD_LIQ_PARAMS =
        IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18});

    IPoolManager.ModifyLiquidityParams internal REMOVE_LIQ_PARAMS =
        IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: -1e18});

    IPoolManager.SwapParams internal SWAP_PARAMS =
        IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: Constants.SQRT_RATIO_1_2});

    uint256 internal DONATE_AMOUNT0 = 12345e6;
    uint256 internal DONATE_AMOUNT1 = 98765e4;

    constructor(IPoolManager _manager, address _user) PoolTestBase(_manager) {
        user = _user;
    }

    function setKey(PoolKey memory _key) external {
        key = _key;
    }

    function execute(Action[] memory actions) public {
        if (Currency.unwrap(key.currency0) == address(0)) revert KeyNotSet();
        for (uint256 i = 0; i < actions.length; i++) {
            Action action = actions[i];
            if (action == Action.NESTED_EXECUTOR_LOCK) _nestedLock();
            else if (action == Action.SWAP_AND_SETTLE) _swap();
            else if (action == Action.ADD_LIQ_AND_SETTLE) _addLiquidity();
            else if (action == Action.REMOVE_LIQ_AND_SETTLE) _removeLiquidity();
            else if (action == Action.DONATE_AND_SETTLE) _donate();
        }
    }

    function _nestedLock() internal {
        (address locker) = manager.getLocker();
        assertEq(locker, msg.sender);

        vm.expectRevert(abi.encodeWithSelector(IPoolManager.AlreadyLocked.selector));
        manager.lock("");

        (locker) = manager.getLocker();
        assertEq(locker, msg.sender);
    }

    function _swap() internal {
        (address locker) = manager.getLocker();
        assertTrue(locker != address(this), "Locker wrong");

        (,,, int256 deltaLockerBefore0) = _fetchBalances(key.currency0, user, locker);
        (,,, int256 deltaLockerBefore1) = _fetchBalances(key.currency1, user, locker);
        (,,, int256 deltaThisBefore0) = _fetchBalances(key.currency0, user, address(this));
        (,,, int256 deltaThisBefore1) = _fetchBalances(key.currency1, user, address(this));

        BalanceDelta delta = manager.swap(key, SWAP_PARAMS, "");

        (,,, int256 deltaLockerAfter0) = _fetchBalances(key.currency0, user, locker);
        (,,, int256 deltaLockerAfter1) = _fetchBalances(key.currency1, user, locker);
        (,,, int256 deltaThisAfter0) = _fetchBalances(key.currency0, user, address(this));
        (,,, int256 deltaThisAfter1) = _fetchBalances(key.currency1, user, address(this));

        assertEq(deltaLockerBefore0, deltaLockerAfter0, "Locker delta 0");
        assertEq(deltaLockerBefore1, deltaLockerAfter1, "Locker delta 1");
        assertEq(deltaThisBefore0 + SWAP_PARAMS.amountSpecified, deltaThisAfter0, "Executor delta 0");
        assertEq(deltaThisBefore1 - 98, deltaThisAfter1, "Executor delta 1");
        assertEq(delta.amount0(), deltaThisAfter0, "Swap delta 0");
        assertEq(delta.amount1(), deltaThisAfter1, "Swap delta 1");

        _settle(key.currency0, user, int128(deltaThisAfter0), true);
        _take(key.currency1, user, int128(deltaThisAfter1), true);
    }

    function _addLiquidity() internal {
        address locker = manager.getLocker();
        assertTrue(locker != address(this), "Locker wrong");

        (,,, int256 deltaLockerBefore0) = _fetchBalances(key.currency0, user, locker);
        (,,, int256 deltaLockerBefore1) = _fetchBalances(key.currency1, user, locker);
        (,,, int256 deltaThisBefore0) = _fetchBalances(key.currency0, user, address(this));
        (,,, int256 deltaThisBefore1) = _fetchBalances(key.currency1, user, address(this));

        BalanceDelta delta = manager.modifyLiquidity(key, ADD_LIQ_PARAMS, "");

        (,,, int256 deltaLockerAfter0) = _fetchBalances(key.currency0, user, locker);
        (,,, int256 deltaLockerAfter1) = _fetchBalances(key.currency1, user, locker);
        (,,, int256 deltaThisAfter0) = _fetchBalances(key.currency0, user, address(this));
        (,,, int256 deltaThisAfter1) = _fetchBalances(key.currency1, user, address(this));

        assertEq(deltaLockerBefore0, deltaLockerAfter0, "Locker delta 0");
        assertEq(deltaLockerBefore1, deltaLockerAfter1, "Locker delta 1");
        assertEq(deltaThisBefore0 + delta.amount0(), deltaThisAfter0, "Executor delta 0");
        assertEq(deltaThisBefore1 + delta.amount1(), deltaThisAfter1, "Executor delta 1");

        _settle(key.currency0, user, int128(deltaThisAfter0), true);
        _settle(key.currency1, user, int128(deltaThisAfter1), true);
    }

    // cannot remove non-existent liquidity - need to perform an add before this removal
    function _removeLiquidity() internal {
        address locker = manager.getLocker();
        assertTrue(locker != address(this), "Locker wrong");

        (,,, int256 deltaLockerBefore0) = _fetchBalances(key.currency0, user, locker);
        (,,, int256 deltaLockerBefore1) = _fetchBalances(key.currency1, user, locker);
        (,,, int256 deltaThisBefore0) = _fetchBalances(key.currency0, user, address(this));
        (,,, int256 deltaThisBefore1) = _fetchBalances(key.currency1, user, address(this));

        BalanceDelta delta = manager.modifyLiquidity(key, REMOVE_LIQ_PARAMS, "");

        (,,, int256 deltaLockerAfter0) = _fetchBalances(key.currency0, user, locker);
        (,,, int256 deltaLockerAfter1) = _fetchBalances(key.currency1, user, locker);
        (,,, int256 deltaThisAfter0) = _fetchBalances(key.currency0, user, address(this));
        (,,, int256 deltaThisAfter1) = _fetchBalances(key.currency1, user, address(this));

        assertEq(deltaLockerBefore0, deltaLockerAfter0, "Locker delta 0");
        assertEq(deltaLockerBefore1, deltaLockerAfter1, "Locker delta 1");
        assertEq(deltaThisBefore0 + delta.amount0(), deltaThisAfter0, "Executor delta 0");
        assertEq(deltaThisBefore1 + delta.amount1(), deltaThisAfter1, "Executor delta 1");

        _take(key.currency0, user, int128(deltaThisAfter0), true);
        _take(key.currency1, user, int128(deltaThisAfter1), true);
    }

    function _donate() internal {
        address locker = manager.getLocker();
        assertTrue(locker != address(this), "Locker wrong");

        (,,, int256 deltaLockerBefore0) = _fetchBalances(key.currency0, user, locker);
        (,,, int256 deltaLockerBefore1) = _fetchBalances(key.currency1, user, locker);
        (,,, int256 deltaThisBefore0) = _fetchBalances(key.currency0, user, address(this));
        (,,, int256 deltaThisBefore1) = _fetchBalances(key.currency1, user, address(this));

        BalanceDelta delta = manager.donate(key, DONATE_AMOUNT0, DONATE_AMOUNT1, "");

        (,,, int256 deltaLockerAfter0) = _fetchBalances(key.currency0, user, locker);
        (,,, int256 deltaLockerAfter1) = _fetchBalances(key.currency1, user, locker);
        (,,, int256 deltaThisAfter0) = _fetchBalances(key.currency0, user, address(this));
        (,,, int256 deltaThisAfter1) = _fetchBalances(key.currency1, user, address(this));

        assertEq(deltaLockerBefore0, deltaLockerAfter0, "Locker delta 0");
        assertEq(deltaLockerBefore1, deltaLockerAfter1, "Locker delta 1");
        assertEq(deltaThisBefore0 + int256(DONATE_AMOUNT0), deltaThisAfter0, "Executor delta 0");
        assertEq(deltaThisBefore1 + int256(DONATE_AMOUNT1), deltaThisAfter1, "Executor delta 1");
        assertEq(delta.amount0(), int256(DONATE_AMOUNT0), "Donate delta 0");
        assertEq(delta.amount1(), int256(DONATE_AMOUNT1), "Donate delta 1");

        _settle(key.currency0, user, int128(deltaThisAfter0), true);
        _settle(key.currency1, user, int128(deltaThisAfter1), true);
    }

    // This will never actually be used - its just to allow us to use the PoolTestBase helper contact
    function lockAcquired(bytes calldata) external pure override returns (bytes memory) {
        return "";
    }
}
