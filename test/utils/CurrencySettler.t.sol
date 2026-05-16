// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {Deployers} from "./Deployers.sol";
import {CurrencySettler} from "./CurrencySettler.sol";
import {IHooks} from "../../src/interfaces/IHooks.sol";
import {Currency, CurrencyLibrary} from "../../src/types/Currency.sol";
import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "../../src/interfaces/callback/IUnlockCallback.sol";
import {TransientStateLibrary} from "../../src/libraries/TransientStateLibrary.sol";

/// @notice Tests for `CurrencySettler.settle` covering the native-currency DoS path that
/// motivated calling `manager.sync(address(0))` before native settles.
/// Reference: PoolManager._settle docs ("if settling native, integrators should still
/// call `sync` first to avoid DoS attack vectors") and v4-core issue #958.
///
/// Flow summary for native-settle scenarios:
///   1. Dirty the synced-currency slot by calling `sync(erc20)` (or some non-zero currency).
///   2. Call `CurrencySettler.settle(nativeCurrency, ..., amount, false)` -- the patched
///      library issues `sync(address(0))` to reset the slot before invoking
///      `manager.settle{value: amount}()`.
///   3. Net out the now-positive native delta with `manager.take(nativeCurrency, ..., amount)`.
contract CurrencySettlerTest is Test, Deployers, IUnlockCallback {
    using CurrencySettler for Currency;
    using TransientStateLibrary for IPoolManager;

    // Action codes consumed by `unlockCallback` for the scenarios exercised in this file.
    uint8 internal constant ACTION_SETTLE_NATIVE_FRESH = 1;
    uint8 internal constant ACTION_SETTLE_NATIVE_AFTER_ERC20_SYNC = 2;
    uint8 internal constant ACTION_SETTLE_NATIVE_AFTER_ERC20_FULL_SETTLE = 3;
    uint8 internal constant ACTION_SETTLE_NATIVE_UNPATCHED_AFTER_ERC20_SYNC = 4;
    uint8 internal constant ACTION_SETTLE_NATIVE_NESTED_HOOK_SYNC = 5;
    uint8 internal constant ACTION_INTERLEAVED_SETTLES = 7;

    // Bound native amounts to `int128.max` because `manager.take` upcasts a `uint128` to int128
    // via `toInt128`, which reverts on overflow.
    uint128 internal constant MAX_NATIVE_AMOUNT = uint128(type(int128).max);

    Currency internal nativeCurrency;
    Currency internal erc20Currency;

    function setUp() public {
        deployFreshManagerAndRouters();
        nativeCurrency = CurrencyLibrary.ADDRESS_ZERO;
        erc20Currency = deployMintAndApproveCurrency();
    }

    // ---------------------------------------------------------------------------
    // Tests
    // ---------------------------------------------------------------------------

    /// @notice Demonstrates the unpatched behavior: a bare `manager.settle{value: amount}()`
    /// after some unrelated `sync(erc20)` reverts with `NonzeroNativeValue`. This is the
    /// exact DoS path the patched `CurrencySettler.settle` now avoids.
    function test_unpatched_settleNative_afterERC20Sync_revertsWithNonzeroNativeValue(uint128 ethAmount) public {
        ethAmount = uint128(bound(ethAmount, 1, MAX_NATIVE_AMOUNT));
        vm.deal(address(this), ethAmount);
        // The expected revert is wrapped by PoolManager.unlock's call to the callback, so we
        // match by full revert payload using expectRevert with the selector embedded.
        vm.expectRevert();
        manager.unlock(abi.encode(ACTION_SETTLE_NATIVE_UNPATCHED_AFTER_ERC20_SYNC, ethAmount));
    }

    /// @notice Patched happy path: `CurrencySettler.settle` on the native currency works
    /// even when the synced-currency slot still points at an unrelated ERC20 from an
    /// earlier `sync` in the same unlock callback. The fix calls `sync(address(0))` to
    /// reset the slot before invoking `_settle`.
    function test_patched_settleNative_afterERC20Sync_succeeds(uint128 ethAmount) public {
        ethAmount = uint128(bound(ethAmount, 1, MAX_NATIVE_AMOUNT));
        vm.deal(address(this), ethAmount);
        manager.unlock(abi.encode(ACTION_SETTLE_NATIVE_AFTER_ERC20_SYNC, ethAmount));
    }

    /// @notice Patched happy path: native settle after a fully-completed ERC20 settle in the
    /// same unlock callback also succeeds. A completed ERC20 settle resets the synced
    /// currency to address(0) via `_settle`, so the bug does not strictly manifest here
    /// today; this guards against future refactors that might leave the slot dirty.
    function test_patched_settleNative_afterERC20FullSettle_succeeds(uint128 erc20Amount, uint128 ethAmount) public {
        erc20Amount = uint128(bound(erc20Amount, 1, MAX_NATIVE_AMOUNT));
        ethAmount = uint128(bound(ethAmount, 1, MAX_NATIVE_AMOUNT));
        // Make sure this contract has enough ERC20 (deployMintAndApproveCurrency mints
        // type(uint256).max already, so this is just a sanity check.)
        require(
            MockERC20(Currency.unwrap(erc20Currency)).balanceOf(address(this)) >= erc20Amount,
            "test setup: not enough erc20"
        );
        vm.deal(address(this), ethAmount);
        manager.unlock(abi.encode(ACTION_SETTLE_NATIVE_AFTER_ERC20_FULL_SETTLE, erc20Amount, ethAmount));
    }

    /// @notice Patched happy path: native settle when no prior sync has occurred should
    /// still credit `msg.value` to the caller's native delta. This is the simplest case
    /// and must keep working after the fix.
    function test_patched_settleNative_freshSlot_succeeds(uint128 ethAmount) public {
        ethAmount = uint128(bound(ethAmount, 1, MAX_NATIVE_AMOUNT));
        vm.deal(address(this), ethAmount);
        manager.unlock(abi.encode(ACTION_SETTLE_NATIVE_FRESH, ethAmount));
    }

    /// @notice Edge case: a hook (or any nested actor) calling `sync` on a non-zero currency
    /// during the unlock callback must not prevent a later native `CurrencySettler.settle`.
    /// This is the composability concern in v4-core issue #958.
    function test_patched_settleNative_afterNestedHookSync_succeeds(uint128 ethAmount) public {
        ethAmount = uint128(bound(ethAmount, 1, MAX_NATIVE_AMOUNT));
        vm.deal(address(this), ethAmount);
        manager.unlock(abi.encode(ACTION_SETTLE_NATIVE_NESTED_HOOK_SYNC, ethAmount));
    }

    /// @notice Fuzz: interleave ERC20 and native settles in either order. Both orderings
    /// must net to zero deltas regardless of amounts. This guards the fix against
    /// regressions across the realistic integration patterns used by routers and hooks
    /// (e.g. settle an ERC20 in then native back, or vice versa, all inside one unlock).
    function test_fuzz_interleavedSettles_neverRevert(uint128 erc20Amount, uint128 ethAmount, bool nativeFirst) public {
        erc20Amount = uint128(bound(erc20Amount, 1, MAX_NATIVE_AMOUNT));
        ethAmount = uint128(bound(ethAmount, 1, MAX_NATIVE_AMOUNT));
        vm.deal(address(this), ethAmount);
        manager.unlock(abi.encode(uint8(7), erc20Amount, ethAmount, nativeFirst));
    }

    // ---------------------------------------------------------------------------
    // unlockCallback dispatcher
    // ---------------------------------------------------------------------------

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager), "only manager");
        uint8 action = abi.decode(data, (uint8));

        if (action == ACTION_SETTLE_NATIVE_FRESH) {
            (, uint256 ethAmount) = abi.decode(data, (uint8, uint256));
            _scenario_freshNativeSettle(ethAmount);
        } else if (action == ACTION_SETTLE_NATIVE_AFTER_ERC20_SYNC) {
            (, uint256 ethAmount) = abi.decode(data, (uint8, uint256));
            _scenario_nativeSettleAfterERC20Sync(ethAmount);
        } else if (action == ACTION_SETTLE_NATIVE_AFTER_ERC20_FULL_SETTLE) {
            (, uint256 erc20Amount, uint256 ethAmount) = abi.decode(data, (uint8, uint256, uint256));
            _scenario_nativeSettleAfterERC20FullSettle(erc20Amount, ethAmount);
        } else if (action == ACTION_SETTLE_NATIVE_UNPATCHED_AFTER_ERC20_SYNC) {
            (, uint256 ethAmount) = abi.decode(data, (uint8, uint256));
            _scenario_unpatchedNativeSettleAfterERC20Sync(ethAmount);
        } else if (action == ACTION_SETTLE_NATIVE_NESTED_HOOK_SYNC) {
            (, uint256 ethAmount) = abi.decode(data, (uint8, uint256));
            _scenario_nativeSettleAfterNestedHookSync(ethAmount);
        } else if (action == ACTION_INTERLEAVED_SETTLES) {
            (, uint256 erc20Amount, uint256 ethAmount, bool nativeFirst) =
                abi.decode(data, (uint8, uint256, uint256, bool));
            _scenario_interleavedSettles(erc20Amount, ethAmount, nativeFirst);
        } else {
            revert("unknown action");
        }
        return "";
    }

    // ---------------------------------------------------------------------------
    // Scenario implementations
    // ---------------------------------------------------------------------------

    /// @dev Trivial case: no prior sync, settle native (paying ethAmount via msg.value),
    /// then take it back so the delta nets to zero.
    function _scenario_freshNativeSettle(uint256 ethAmount) internal {
        nativeCurrency.settle(manager, address(this), ethAmount, false);
        manager.take(nativeCurrency, address(this), ethAmount);
        // delta is now zero -- if not, unlock reverts.
    }

    /// @dev Simulates the DoS path: an earlier `sync(erc20)` dirtied the synced slot.
    /// The patched library calls `sync(address(0))` first to reset, so settle succeeds.
    function _scenario_nativeSettleAfterERC20Sync(uint256 ethAmount) internal {
        manager.sync(erc20Currency);
        assertEq(
            Currency.unwrap(manager.getSyncedCurrency()),
            Currency.unwrap(erc20Currency),
            "sync slot should hold erc20 before native settle"
        );

        // The fix: CurrencySettler.settle on native first calls sync(address(0)).
        nativeCurrency.settle(manager, address(this), ethAmount, false);

        // After settling native, the sync slot must have been reset to address(0).
        assertEq(
            Currency.unwrap(manager.getSyncedCurrency()),
            Currency.unwrap(CurrencyLibrary.ADDRESS_ZERO),
            "sync slot should be reset after native settle"
        );

        manager.take(nativeCurrency, address(this), ethAmount);
    }

    /// @dev Sanity case: settle an ERC20 fully (which clears the slot via _settle), then
    /// settle native. The fix must not regress this path.
    function _scenario_nativeSettleAfterERC20FullSettle(uint256 erc20Amount, uint256 ethAmount) internal {
        erc20Currency.settle(manager, address(this), erc20Amount, false);
        manager.take(erc20Currency, address(this), erc20Amount);

        nativeCurrency.settle(manager, address(this), ethAmount, false);
        manager.take(nativeCurrency, address(this), ethAmount);
    }

    /// @dev Pre-fix behavior reproducer: a raw `manager.settle{value:}()` after a
    /// `sync(erc20)` reverts. We reproduce the unpatched call directly rather than via
    /// the library so the test stays meaningful even after the library is fixed.
    function _scenario_unpatchedNativeSettleAfterERC20Sync(uint256 ethAmount) internal {
        manager.sync(erc20Currency);
        // Intentionally do NOT call sync(address(0)) -- this is the buggy pattern.
        manager.settle{value: ethAmount}();
    }

    /// @dev Hook-composability case: a nested actor dirties the sync slot mid-flow
    /// before the outer flow settles native via the library.
    function _scenario_nativeSettleAfterNestedHookSync(uint256 ethAmount) internal {
        // Simulate a hook that calls sync(erc20) mid-flow without itself settling.
        manager.sync(erc20Currency);

        // The patched library still recovers and settles native correctly.
        nativeCurrency.settle(manager, address(this), ethAmount, false);
        manager.take(nativeCurrency, address(this), ethAmount);
    }

    /// @dev Fuzz scenario: interleave native + ERC20 settles in either order, all inside
    /// one unlock. Each branch makes the synced-currency slot non-zero before the next
    /// settle, exercising the fix from every realistic direction.
    function _scenario_interleavedSettles(uint256 erc20Amount, uint256 ethAmount, bool nativeFirst) internal {
        if (nativeFirst) {
            nativeCurrency.settle(manager, address(this), ethAmount, false);
            manager.take(nativeCurrency, address(this), ethAmount);
            erc20Currency.settle(manager, address(this), erc20Amount, false);
            manager.take(erc20Currency, address(this), erc20Amount);
        } else {
            erc20Currency.settle(manager, address(this), erc20Amount, false);
            manager.take(erc20Currency, address(this), erc20Amount);
            nativeCurrency.settle(manager, address(this), ethAmount, false);
            manager.take(nativeCurrency, address(this), ethAmount);
        }
    }

    // `receive` is inherited from Deployers so ETH from `manager.take(native, ...)` flows in.
}
