// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Currency, CurrencyLibrary} from "../types/Currency.sol";
import {IERC20Minimal} from "../interfaces/external/IERC20Minimal.sol";

import {ILockCallback} from "../interfaces/callback/ILockCallback.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";

contract PoolTakeTest is ILockCallback {
    using CurrencyLibrary for Currency;

    IPoolManager public immutable manager;
    Currency public immutable WRAPPED_NATIVE;

    constructor(IPoolManager _manager) {
        manager = _manager;
        WRAPPED_NATIVE = manager.WRAPPED_NATIVE();
    }

    struct CallbackData {
        address sender;
        Currency currency0;
        Currency currency1;
        uint256 amount0;
        uint256 amount1;
    }

    function take(Currency currency0, Currency currency1, uint256 amount0, uint256 amount1) public payable {
        manager.lock(abi.encode(CallbackData(msg.sender, currency0, currency1, amount0, amount1)));
    }

    function lockAcquired(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        if (data.amount0 > 0) takeAndSettle(data.currency0, data.amount0, data.sender);
        if (data.amount1 > 0) takeAndSettle(data.currency1, data.amount1, data.sender);

        return abi.encode(0);
    }

    function takeAndSettle(Currency currency, uint256 amount, address sender) internal {
        Currency accountCurrency = (currency == WRAPPED_NATIVE) ? CurrencyLibrary.NATIVE : currency;

        uint256 balBefore = currency.balanceOf(sender);
        uint256 reservesBefore = manager.reservesOf(accountCurrency);
        require(WRAPPED_NATIVE.balanceOf(address(manager)) == 0);

        manager.take(currency, sender, amount);

        uint256 balAfter = currency.balanceOf(sender);
        uint256 reservesAfter = manager.reservesOf(accountCurrency);
        require(WRAPPED_NATIVE.balanceOf(address(manager)) == 0);

        require(balAfter - balBefore == amount);
        require(reservesBefore - reservesAfter == amount);

        if (currency.isNative()) {
            manager.settle{value: uint256(amount)}(currency);
        } else {
            IERC20Minimal(Currency.unwrap(currency)).transferFrom(sender, address(manager), uint256(amount));
            manager.settle(currency);
        }
    }
}
