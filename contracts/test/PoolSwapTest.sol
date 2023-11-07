// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {CurrencyLibrary, Currency} from "../types/Currency.sol";
import {IERC20Minimal} from "../interfaces/external/IERC20Minimal.sol";

import {ILockCallback} from "../interfaces/callback/ILockCallback.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {console2} from "forge-std/console2.sol";

contract PoolSwapTest is ILockCallback {
    using CurrencyLibrary for Currency;

    error NoSwapOccurred();

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
        bool settleUsingWrapped;
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
        
        // make sure youve added liquidity to the test pool!
        if (BalanceDelta.unwrap(delta) == 0) revert NoSwapOccurred();

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
        console2.log('swapandsettle');
        if (deltaA > 0) {
            console2.log('deltaApositive');
            if (settings.settleUsingTransfer) {
                console2.log('transfer');
                if (currencyA.isNative()) {
                    console2.log('isnative');
                    if (!settings.settleUsingWrapped) manager.settle{value: uint128(deltaA)}(currencyA);
                    else {
                        IERC20Minimal(Currency.unwrap(WRAPPED_NATIVE)).transferFrom(sender, address(manager), uint128(deltaA));
                        manager.settle(WRAPPED_NATIVE);
                    }
                } else {
                    IERC20Minimal(Currency.unwrap(currencyA)).transferFrom(sender, address(manager), uint128(deltaA));
                    manager.settle(currencyA);
                }
            } else {
                console2.log('transferFrom');
                // the received hook on this transfer will burn the tokens
                manager.safeTransferFrom(
                    sender, address(manager), uint256(uint160(Currency.unwrap(currencyA))), uint128(deltaA), ""
                );
            }
        }
        if (deltaB < 0) {
            console2.log('deltaBnegative');
            if (settings.withdrawTokens) {
                console2.log('take');
                manager.take(currencyB, sender, uint128(-deltaB));
            } else {
                console2.log('mint');
                manager.mint(currencyB, sender, uint128(-deltaB));
            }
        }
    }
}
