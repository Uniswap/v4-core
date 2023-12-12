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

    constructor(IPoolManager _manager) {
        manager = _manager;
        executor = new NestedActionExecutor(manager);
    }

    function lock(Action[] memory actions) external {
        manager.lock(address(this), abi.encode(actions));
    }

    /// @notice Called by the pool manager on `msg.sender` when a lock is acquired
    function lockAcquired(address, bytes calldata data) external override returns (bytes memory) {
        Action[] memory actions = abi.decode(data, (Action[]));
        if (actions.length == 1 && actions[0] == Action.NESTED_SELF_LOCK) {
            _nestedLock();
        } else {
            executor.execute(actions);
        }
        return "";
    }

    function _nestedLock() internal {
        (address locker, address lockCaller) = manager.getLock();
        assertEq(locker, address(this));
        assertEq(lockCaller, address(this));

        vm.expectRevert(abi.encodeWithSelector(IPoolManager.LockedBy.selector, address(this)));
        manager.lock(address(this), "");

        (locker, lockCaller) = manager.getLock();
        assertEq(locker, address(this));
        assertEq(lockCaller, address(this));
    }
}

contract NestedActionExecutor is Test, PoolTestBase {
    PoolKey internal key;

    error KeyNotSet();

    IPoolManager.ModifyPositionParams internal ADD_LIQ_PARAMS =
        IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18});

    IPoolManager.ModifyPositionParams internal REMOVE_LIQ_PARAMS =
        IPoolManager.ModifyPositionParams({tickLower: -120, tickUpper: 120, liquidityDelta: -1e18});

    IPoolManager.SwapParams internal SWAP_PARAMS =
        IPoolManager.SwapParams({zeroForOne: true, amountSpecified: 100, sqrtPriceLimitX96: Constants.SQRT_RATIO_1_2});

    constructor(IPoolManager _manager) PoolTestBase(_manager) {}

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
        (address locker, address lockCaller) = manager.getLock();
        assertEq(locker, msg.sender);
        assertEq(lockCaller, msg.sender);

        vm.expectRevert(abi.encodeWithSelector(IPoolManager.LockedBy.selector, msg.sender));
        manager.lock(address(this), "");

        (locker, lockCaller) = manager.getLock();
        assertEq(locker, msg.sender);
        assertEq(lockCaller, msg.sender);
    }

    function _swap() internal {
        // swap without a lock, checking that the deltas are applied to this contract's address
        (,,, int256 deltaLockerBefore0) = _fetchBalances(key.currency0, msg.sender);
        (,,, int256 deltaLockerBefore1) = _fetchBalances(key.currency1, msg.sender);
        (,,, int256 deltaThisBefore0) = _fetchBalances(key.currency0, address(this));
        (,,, int256 deltaThisBefore1) = _fetchBalances(key.currency1, address(this));

        BalanceDelta delta = manager.swap(key, SWAP_PARAMS, "");

        (,,, int256 deltaLockerAfter0) = _fetchBalances(key.currency0, msg.sender);
        (,,, int256 deltaLockerAfter1) = _fetchBalances(key.currency1, msg.sender);
        (,,, int256 deltaThisAfter0) = _fetchBalances(key.currency0, address(this));
        (,,, int256 deltaThisAfter1) = _fetchBalances(key.currency1, address(this));

        assertEq(deltaLockerBefore0, deltaLockerAfter0);
        assertEq(deltaLockerBefore1, deltaLockerAfter1);
        assertEq(deltaThisBefore0 + SWAP_PARAMS.amountSpecified, deltaThisAfter0);
        assertEq(deltaThisBefore1 - 98, deltaThisAfter1);
        assertEq(delta.amount0(), deltaThisAfter0);
        assertEq(delta.amount1(), deltaThisAfter1);
    }

    function _addLiquidity() internal {}
    function _removeLiquidity() internal {}
    function _donate() internal {}

    // This will never actually be used - its just to allow us to use the PoolTestBase helper contact
    function lockAcquired(address, bytes calldata) external pure override returns (bytes memory) {
        return "";
    }
}
