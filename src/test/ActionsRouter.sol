// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {IUnlockCallback} from "../interfaces/callback/IUnlockCallback.sol";
import {Currency} from "../types/Currency.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {StateLibrary} from "../libraries/StateLibrary.sol";
import {TransientStateLibrary} from "../libraries/TransientStateLibrary.sol";

// Supported Actions.
enum Actions {
    SETTLE,
    SETTLE_NATIVE,
    SETTLE_FOR,
    TAKE,
    PRANK_TAKE_FROM,
    SYNC,
    MINT,
    CLEAR,
    ASSERT_BALANCE_EQUALS,
    ASSERT_RESERVES_EQUALS,
    ASSERT_DELTA_EQUALS,
    ASSERT_NONZERO_DELTA_COUNT_EQUALS,
    TRANSFER_FROM,
    COLLECT_PROTOCOL_FEES
}
// TODO: Add other actions as needed.
// BURN,
// MODIFY_POSITION,
// INITIALIZE,
// DONATE

/// @notice A router that handles an arbitrary input of actions.
/// TODO: Can continue to add functions per action.
contract ActionsRouter is IUnlockCallback, Test {
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;

    error ActionNotSupported();

    // error thrown so that incorrectly formatted tests don't pass silently
    error CheckParameters();

    IPoolManager manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        (Actions[] memory actions, bytes[] memory params) = abi.decode(data, (Actions[], bytes[]));
        if (actions.length != params.length || actions.length == 0) revert CheckParameters();
        for (uint256 i = 0; i < actions.length; i++) {
            Actions action = actions[i];
            bytes memory param = params[i];
            if (action == Actions.SETTLE) {
                _settle();
            } else if (action == Actions.SETTLE_NATIVE) {
                _settleNative(param);
            } else if (action == Actions.SETTLE_FOR) {
                _settleFor(param);
            } else if (action == Actions.TAKE) {
                _take(param);
            } else if (action == Actions.PRANK_TAKE_FROM) {
                _prankTakeFrom(param);
            } else if (action == Actions.SYNC) {
                _sync(param);
            } else if (action == Actions.MINT) {
                _mint(param);
            } else if (action == Actions.CLEAR) {
                _clear(param);
            } else if (action == Actions.ASSERT_BALANCE_EQUALS) {
                _assertBalanceEquals(param);
            } else if (action == Actions.ASSERT_RESERVES_EQUALS) {
                _assertReservesEquals(param);
            } else if (action == Actions.ASSERT_DELTA_EQUALS) {
                _assertDeltaEquals(param);
            } else if (action == Actions.ASSERT_NONZERO_DELTA_COUNT_EQUALS) {
                _assertNonzeroDeltaCountEquals(param);
            } else if (action == Actions.TRANSFER_FROM) {
                _transferFrom(param);
            } else if (action == Actions.COLLECT_PROTOCOL_FEES) {
                _collectProtocolFees(param);
            }
        }
        return "";
    }

    function executeActions(Actions[] memory actions, bytes[] memory params) external payable {
        manager.unlock(abi.encode(actions, params));
    }

    function _settle() internal {
        manager.settle();
    }

    function _settleNative(bytes memory params) internal {
        uint256 amount = abi.decode(params, (uint256));
        manager.settle{value: amount}();
    }

    function _settleFor(bytes memory params) internal {
        address recipient = abi.decode(params, (address));
        manager.settleFor(recipient);
    }

    function _take(bytes memory params) internal {
        (Currency currency, address recipient, int128 amount) = abi.decode(params, (Currency, address, int128));
        manager.take(currency, recipient, uint128(amount));
    }

    function _prankTakeFrom(bytes memory params) internal {
        (Currency currency, address from, address recipient, uint256 amount) =
            abi.decode(params, (Currency, address, address, uint256));
        vm.prank(from);
        manager.take(currency, recipient, amount);
    }

    function _sync(bytes memory params) internal {
        Currency currency = Currency.wrap(abi.decode(params, (address)));
        manager.sync(currency);
    }

    function _mint(bytes memory params) internal {
        (address recipient, Currency currency, uint256 amount) = abi.decode(params, (address, Currency, uint256));
        manager.mint(recipient, currency.toId(), amount);
    }

    function _clear(bytes memory params) internal {
        (Currency currency, uint256 amount, bool measureGas, string memory gasSnapName) =
            abi.decode(params, (Currency, uint256, bool, string));

        manager.clear(currency, amount);
        if (measureGas) vm.snapshotGasLastCall(gasSnapName);
    }

    function _assertBalanceEquals(bytes memory params) internal view {
        (Currency currency, address user, uint256 expectedBalance) = abi.decode(params, (Currency, address, uint256));
        assertEq(currency.balanceOf(user), expectedBalance, "usertoken value incorrect");
    }

    function _assertReservesEquals(bytes memory params) internal view {
        uint256 expectedReserves = abi.decode(params, (uint256));
        assertEq(manager.getSyncedReserves(), expectedReserves, "reserves value incorrect");
    }

    function _assertDeltaEquals(bytes memory params) internal view {
        (Currency currency, address caller, int256 expectedDelta) = abi.decode(params, (Currency, address, int256));

        assertEq(manager.currencyDelta(caller, currency), expectedDelta, "delta value incorrect");
    }

    function _assertNonzeroDeltaCountEquals(bytes memory params) internal view {
        (uint256 expectedCount) = abi.decode(params, (uint256));
        assertEq(manager.getNonzeroDeltaCount(), expectedCount, "nonzero delta count incorrect");
    }

    function _transferFrom(bytes memory params) internal {
        (Currency currency, address from, address recipient, uint256 amount) =
            abi.decode(params, (Currency, address, address, uint256));
        MockERC20(Currency.unwrap(currency)).transferFrom(from, recipient, uint256(amount));
    }

    function _collectProtocolFees(bytes memory params) internal {
        (address to, Currency currency, uint256 amount) = abi.decode(params, (address, Currency, uint256));
        manager.collectProtocolFees(to, currency, amount);
    }
}
