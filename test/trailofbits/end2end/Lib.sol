// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IHooks} from "src/interfaces/IHooks.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";

import {Hooks} from "src/libraries/Hooks.sol";
import {TickMath} from "src/libraries/TickMath.sol";
import {Deployers} from "test/utils/Deployers.sol";
import {StateLibrary} from "src/libraries/StateLibrary.sol";
import {PoolId, PoolIdLibrary} from "src/types/PoolId.sol";
import {PoolKey} from "src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "src/types/Currency.sol";

import {PropertiesAsserts} from "../PropertiesHelper.sol";

struct SwapInfo {
    Currency fromCurrency;
    Currency toCurrency;
    address User;
    int256 fromBalanceBefore;
    int256 toBalanceBefore;
    int256 fromBalanceAfter;
    int256 toBalanceAfter;
    int256 fromDelta;
    int256 toDelta;
}

library SwapInfoLibrary {
    function initialize(Currency fromCurrency, Currency toCurrency, address user)
        internal
        view
        returns (SwapInfo memory)
    {
        return SwapInfo({
            User: user,
            fromCurrency: fromCurrency,
            toCurrency: toCurrency,
            fromBalanceBefore: int256(fromCurrency.balanceOf(user)),
            toBalanceBefore: int256(toCurrency.balanceOf(user)),
            fromBalanceAfter: 0,
            toBalanceAfter: 0,
            fromDelta: 0,
            toDelta: 0
        });
    }

    function captureSwapResults(SwapInfo memory s) internal view {
        s.fromBalanceAfter = int256(s.fromCurrency.balanceOf(s.User));
        s.toBalanceAfter = int256(s.toCurrency.balanceOf(s.User));
        s.fromDelta = int256(s.fromBalanceAfter) - int256(s.fromBalanceBefore);
        s.toDelta = int256(s.toBalanceAfter) - int256(s.toBalanceBefore);
    }
}

using SwapInfoLibrary for SwapInfo global;
