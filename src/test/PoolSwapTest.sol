// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {CurrencyLibrary, Currency} from "../types/Currency.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../types/BalanceDelta.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {Hooks} from "../libraries/Hooks.sol";
import {PoolTestBase} from "./PoolTestBase.sol";
import {Test} from "forge-std/Test.sol";
import {Hooks} from "../libraries/Hooks.sol";
import {IHooks} from "../interfaces/IHooks.sol";

contract PoolSwapTest is Test, PoolTestBase {
    using CurrencyLibrary for Currency;
    using Hooks for IHooks;

    constructor(IPoolManager _manager) PoolTestBase(_manager) {}

    error NoSwapOccurred();

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
        bool currencyAlreadySent;
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

        (,, uint256 reserveBefore0, int256 deltaBefore0) =
            _fetchBalances(data.key.currency0, data.sender, address(this));
        (,, uint256 reserveBefore1, int256 deltaBefore1) =
            _fetchBalances(data.key.currency1, data.sender, address(this));

        assertEq(deltaBefore0, 0);
        assertEq(deltaBefore1, 0);

        BalanceDelta delta = manager.swap(data.key, data.params, data.hookData);

        (,, uint256 reserveAfter0, int256 deltaAfter0) = _fetchBalances(data.key.currency0, data.sender, address(this));
        (,, uint256 reserveAfter1, int256 deltaAfter1) = _fetchBalances(data.key.currency1, data.sender, address(this));

        assertEq(reserveBefore0, reserveAfter0);
        assertEq(reserveBefore1, reserveAfter1);

        if (data.params.zeroForOne) {
            if (data.params.amountSpecified < 0) {
                // exact input, 0 for 1
                assertEq(deltaAfter0, data.params.amountSpecified);
                assertGt(deltaAfter1, 0);
            } else {
                // exact output, 0 for 1
                assertLt(deltaAfter0, 0);
                assertEq(deltaAfter1, data.params.amountSpecified);
            }
        } else {
            if (data.params.amountSpecified < 0) {
                // exact input, 1 for 0
                assertEq(deltaAfter1, data.params.amountSpecified);
                assertGt(deltaAfter0, 0);
            } else {
                // exact output, 1 for 0
                assertLt(deltaAfter1, 0);
                assertEq(deltaAfter0, data.params.amountSpecified);
            }
        }

        if (deltaAfter0 < 0) {
            if (data.testSettings.currencyAlreadySent) {
                manager.settle(data.key.currency0);
            } else {
                _settle(data.key.currency0, data.sender, int128(deltaAfter0), data.testSettings.settleUsingTransfer);
            }
        }
        if (deltaAfter1 < 0) {
            if (data.testSettings.currencyAlreadySent) {
                manager.settle(data.key.currency1);
            } else {
                _settle(data.key.currency1, data.sender, int128(deltaAfter1), data.testSettings.settleUsingTransfer);
            }
        }
        if (deltaAfter0 > 0) {
            _take(data.key.currency0, data.sender, int128(deltaAfter0), data.testSettings.withdrawTokens);
        }
        if (deltaAfter1 > 0) {
            _take(data.key.currency1, data.sender, int128(deltaAfter1), data.testSettings.withdrawTokens);
        }

        return abi.encode(delta);
    }
}
