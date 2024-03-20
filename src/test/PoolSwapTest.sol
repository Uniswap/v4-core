// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {CurrencyLibrary, Currency} from "../types/Currency.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../types/BalanceDelta.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {Hooks} from "../libraries/Hooks.sol";
import {PoolTestBase} from "./PoolTestBase.sol";
import {Hooks} from "../libraries/Hooks.sol";
import {IHooks} from "../interfaces/IHooks.sol";

contract PoolSwapTest is PoolTestBase {
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
            manager.unlock(abi.encode(CallbackData(msg.sender, testSettings, key, params, hookData))), (BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        (,, uint256 reserveBefore0, int256 deltaBefore0) =
            _fetchBalances(data.key.currency0, data.sender, address(this));
        (,, uint256 reserveBefore1, int256 deltaBefore1) =
            _fetchBalances(data.key.currency1, data.sender, address(this));

        require(deltaBefore0 == 0, "deltaBefore0 is not equal to 0");
        require(deltaBefore1 == 0, "deltaBefore1 is not equal to 0");

        BalanceDelta delta = manager.swap(data.key, data.params, data.hookData);

        (,, uint256 reserveAfter0, int256 deltaAfter0) = _fetchBalances(data.key.currency0, data.sender, address(this));
        (,, uint256 reserveAfter1, int256 deltaAfter1) = _fetchBalances(data.key.currency1, data.sender, address(this));

        require(reserveBefore0 == reserveAfter0, "reserveBefore0 is not equal to reserveAfter0");
        require(reserveBefore1 == reserveAfter1, "reserveBefore1 is not equal to reserveAfter1");

        if (data.params.zeroForOne) {
            if (data.params.amountSpecified < 0) {
                // exact input, 0 for 1
                require(
                    deltaAfter0 == data.params.amountSpecified,
                    "deltaAfter0 is not equal to data.params.amountSpecified"
                );
                require(deltaAfter1 > 0, "deltaAfter1 is not greater than 0");
            } else {
                // exact output, 0 for 1
                require(deltaAfter0 < 0, "deltaAfter0 is not less than zero");
                require(
                    deltaAfter1 == data.params.amountSpecified,
                    "deltaAfter1 is not equal to data.params.amountSpecified"
                );
            }
        } else {
            if (data.params.amountSpecified < 0) {
                // exact input, 1 for 0
                require(
                    deltaAfter1 == data.params.amountSpecified,
                    "deltaAfter1 is not equal to data.params.amountSpecified"
                );
                require(deltaAfter0 > 0, "deltaAfter0 is not greater than 0");
            } else {
                // exact output, 1 for 0
                require(deltaAfter1 < 0, "deltaAfter1 is not less than 0");
                require(
                    deltaAfter0 == data.params.amountSpecified,
                    "deltaAfter0 is not equal to data.params.amountSpecified"
                );
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
