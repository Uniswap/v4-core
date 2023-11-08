// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {CurrencyLibrary, Currency} from "../types/Currency.sol";
import {IERC20Minimal} from "../interfaces/external/IERC20Minimal.sol";

import {ILockCallback} from "../interfaces/callback/ILockCallback.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {PoolKey} from "../types/PoolKey.sol";

contract PoolSwapTest is ILockCallback {
    using CurrencyLibrary for Currency;

    IPoolManager public immutable manager;
    Currency public immutable WRAPPED_NATIVE;

    constructor(IPoolManager _manager) {
        manager = _manager;
        WRAPPED_NATIVE = manager.WRAPPED_NATIVE();
    }

    struct CallbackData {
        address sender;
        TestSettings testSettings;
        PoolKey key;
        IPoolManager.SwapParams params;
        bytes hookData;
    }

    struct TestSettings {
        bool withdrawTokens;
        bool settleUsingTransfer;
        bool useWrappedNative;
    }

    function swap(
        PoolKey memory key,
        IPoolManager.SwapParams memory params,
        TestSettings memory testSettings,
        bytes memory hookData
    ) external payable returns (BalanceDelta delta) {
        delta = abi.decode(
            manager.lock(abi.encode(CallbackData(msg.sender, testSettings, key, params, hookData))), (BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
    }

    function lockAcquired(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        BalanceDelta delta = manager.swap(data.key, data.params, data.hookData);

        if (data.params.zeroForOne) {
            swapAndSettle(
                data.key.currency0, data.key.currency1, delta.amount0(), delta.amount1(), data.sender, data.testSettings
            );
        } else {
            swapAndSettle(
                data.key.currency1, data.key.currency0, delta.amount1(), delta.amount0(), data.sender, data.testSettings
            );
        }

        return abi.encode(delta);
    }

    function swapAndSettle(
        Currency currencyA,
        Currency currencyB,
        int128 deltaA,
        int128 deltaB,
        address sender,
        TestSettings memory settings
    ) internal {
        if (deltaA > 0) {
            if (settings.settleUsingTransfer) {
                if (currencyA.isNative()) {
                    if (!settings.useWrappedNative) {
                        manager.settle{value: uint128(deltaA)}(currencyA);
                    } else {
                        IERC20Minimal(Currency.unwrap(WRAPPED_NATIVE)).transferFrom(
                            sender, address(manager), uint128(deltaA)
                        );
                        manager.settle(WRAPPED_NATIVE);
                    }
                } else {
                    IERC20Minimal(Currency.unwrap(currencyA)).transferFrom(sender, address(manager), uint128(deltaA));
                    manager.settle(currencyA);
                }
            } else {
                // the received hook on this transfer will burn the tokens
                manager.safeTransferFrom(
                    sender, address(manager), uint256(uint160(Currency.unwrap(currencyA))), uint128(deltaA), ""
                );
            }
        }
        if (deltaB < 0) {
            if (settings.withdrawTokens) {
                Currency takeCurrency = (currencyB.isNative() && settings.useWrappedNative) ? WRAPPED_NATIVE : currencyB;
                manager.take(takeCurrency, sender, uint128(-deltaB));
            } else {
                manager.mint(currencyB, sender, uint128(-deltaB));
            }
        }
    }
}
