// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Currency, CurrencyLibrary} from "../types/Currency.sol";
import {IERC20Minimal} from "../interfaces/external/IERC20Minimal.sol";

import {ILockCallback} from "../interfaces/callback/ILockCallback.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";

contract PoolTakeTest is ILockCallback {
    using CurrencyLibrary for Currency;

    IPoolManager public immutable manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    struct CallbackData {
        address sender;
        PoolKey key;
        uint256 amount0;
        uint256 amount1;
    }

    function take(PoolKey memory key, uint256 amount0, uint256 amount1) external payable {
        manager.lock(abi.encode(CallbackData(msg.sender, key, amount0, amount1)));
    }

    function balanceOf(Currency currency, address user) internal view returns (uint256) {
        if (currency.isNative()) {
            return user.balance;
        } else {
            return IERC20Minimal(Currency.unwrap(currency)).balanceOf(user);
        }
    }

    function lockAcquired(uint256, bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        if (data.amount0 > 0) {
            uint256 balBefore = balanceOf(data.key.currency0, data.sender);
            manager.take(data.key.currency0, data.sender, data.amount0);
            uint256 balAfter = balanceOf(data.key.currency0, data.sender);
            require(balAfter - balBefore == data.amount0);

            if (data.key.currency0.isNative()) {
                manager.settle{value: uint256(data.amount0)}(data.key.currency0);
            } else {
                IERC20Minimal(Currency.unwrap(data.key.currency0)).transferFrom(
                    data.sender, address(manager), uint256(data.amount0)
                );
                manager.settle(data.key.currency0);
            }
        }

        if (data.amount1 > 0) {
            uint256 balBefore = balanceOf(data.key.currency1, data.sender);
            manager.take(data.key.currency1, data.sender, data.amount1);
            uint256 balAfter = balanceOf(data.key.currency1, data.sender);
            require(balAfter - balBefore == data.amount1);

            if (data.key.currency1.isNative()) {
                manager.settle{value: uint256(data.amount1)}(data.key.currency1);
            } else {
                IERC20Minimal(Currency.unwrap(data.key.currency1)).transferFrom(
                    data.sender, address(manager), uint256(data.amount1)
                );
                manager.settle(data.key.currency1);
            }
        }

        return abi.encode(0);
    }
}
