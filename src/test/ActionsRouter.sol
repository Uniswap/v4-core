// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {IUnlockCallback} from "../interfaces/callback/IUnlockCallback.sol";
import {Currency, CurrencyLibrary} from "../types/Currency.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

// Supported Actions.
enum Actions {
    SETTLE,
    TAKE,
    SYNC,
    MINT,
    ASSERT_BALANCE_EQUALS,
    ASSERT_RESERVES_EQUALS,
    ASSERT_DELTA_EQUALS,
    TRANSFER_FROM
}
// TODO: Add other actions as needed.
// BURN,
// MODIFY_POSITION,
// INITIALIZE,
// DONATE

/// @notice A router that handles an arbitrary input of actions.
/// TODO: Can continue to add functions per action.
contract ActionsRouter is IUnlockCallback, Test {
    using CurrencyLibrary for Currency;

    error ActionNotSupported();

    IPoolManager manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        (Actions[] memory actions, bytes[] memory params) = abi.decode(data, (Actions[], bytes[]));
        for (uint256 i = 0; i < actions.length; i++) {
            Actions action = actions[i];
            bytes memory param = params[i];
            if (action == Actions.SETTLE) {
                _settle(param);
            } else if (action == Actions.TAKE) {
                _take(param);
            } else if (action == Actions.SYNC) {
                _sync(param);
            } else if (action == Actions.MINT) {
                _mint(param);
            } else if (action == Actions.ASSERT_BALANCE_EQUALS) {
                _assertBalanceEquals(param);
            } else if (action == Actions.ASSERT_RESERVES_EQUALS) {
                _assertReservesEquals(param);
            } else if (action == Actions.ASSERT_DELTA_EQUALS) {
                _assertDeltaEquals(param);
            } else if (action == Actions.TRANSFER_FROM) {
                _transferFrom(param);
            }
        }
    }

    function executeActions(Actions[] memory actions, bytes[] memory params) external {
        manager.unlock(abi.encode(actions, params));
    }

    function _settle(bytes memory params) internal {
        Currency currency = abi.decode(params, (Currency));
        manager.settle(currency);
    }

    function _take(bytes memory params) internal {
        (Currency currency, address recipient, int128 amount) = abi.decode(params, (Currency, address, int128));
        manager.take(currency, recipient, uint128(amount));
    }

    function _sync(bytes memory params) internal {
        Currency currency = Currency.wrap(abi.decode(params, (address)));
        manager.sync(currency);
    }

    function _mint(bytes memory params) internal {
        (address recipient, Currency currency, uint256 amount) = abi.decode(params, (address, Currency, uint256));
        manager.mint(recipient, currency.toId(), amount);
    }

    function _assertBalanceEquals(bytes memory params) internal {
        (Currency currency, address user, uint256 expectedBalance) = abi.decode(params, (Currency, address, uint256));
        assertEq(currency.balanceOf(user), expectedBalance, "usertoken value incorrect");
    }

    function _assertReservesEquals(bytes memory params) internal {
        (Currency currency, uint256 expectedReserves) = abi.decode(params, (Currency, uint256));
        assertEq(manager.getReserves(currency), expectedReserves, "reserves value incorrect");
    }

    function _assertDeltaEquals(bytes memory params) internal {
        (Currency currency, address caller, int256 expectedDelta) = abi.decode(params, (Currency, address, int256));

        assertEq(manager.currencyDelta(caller, currency), expectedDelta, "delta value incorrect");
    }

    function _transferFrom(bytes memory params) internal {
        (Currency currency, address from, address recipient, uint256 amount) =
            abi.decode(params, (Currency, address, address, uint256));
        MockERC20(Currency.unwrap(currency)).transferFrom(from, recipient, uint256(amount));
    }
}
