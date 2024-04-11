// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Hooks} from "../libraries/Hooks.sol";
import {SafeCast} from "../libraries/SafeCast.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta, toBalanceDelta} from "../types/BalanceDelta.sol";
import {Currency} from "../types/Currency.sol";
import {BaseTestHooks} from "./BaseTestHooks.sol";
import {IERC20Minimal} from "../interfaces/external/IERC20Minimal.sol";
import {CurrencyLibrary, Currency} from "../types/Currency.sol";

contract DeltaReturningHook is BaseTestHooks {
    using Hooks for IHooks;
    using CurrencyLibrary for Currency;

    IPoolManager immutable manager;

    int128 deltaSpecified;
    int128 deltaUnspecified;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    modifier onlyPoolManager() {
        require(msg.sender == address(manager));
        _;
    }

    function setDeltaSpecified(int128 delta) external {
        deltaSpecified = delta;
    }

    function setDeltaUnspecified(int128 delta) external {
        deltaUnspecified = delta;
    }

    function beforeSwap(
        address, /* sender **/
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata /* hookData **/
    ) external override onlyPoolManager returns (bytes4, int128, uint24) {
        (Currency specifiedCurrency,) = _sortCurrencies(key, params);
        _settleOrTake(specifiedCurrency, deltaSpecified);

        return (IHooks.beforeSwap.selector, deltaSpecified, type(uint24).max);
    }

    function afterSwap(
        address, /* sender **/
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta, /* delta **/
        bytes calldata /* hookData **/
    ) external override onlyPoolManager returns (bytes4, int128) {
        (, Currency unspecifiedCurrency) = _sortCurrencies(key, params);
        _settleOrTake(unspecifiedCurrency, deltaUnspecified);

        return (IHooks.afterSwap.selector, deltaUnspecified);
    }

    function _sortCurrencies(PoolKey calldata key, IPoolManager.SwapParams calldata params)
        internal
        pure
        returns (Currency specified, Currency unspecified)
    {
        (specified, unspecified) = (params.zeroForOne == (params.amountSpecified < 0))
            ? (key.currency0, key.currency1)
            : (key.currency1, key.currency0);
    }

    function _settleOrTake(Currency currency, int128 delta) internal {
        // positive amount means positive delta for the hook, so it can take
        // negative it should settle
        if (delta > 0) {
            manager.take(currency, address(this), uint128(delta));
        } else {
            uint256 amount = uint256(-int256(delta));
            if (currency.isNative()) {
                manager.settle{value: amount}(currency);
            } else {
                IERC20Minimal(Currency.unwrap(currency)).transfer(address(manager), amount);
                manager.settle(currency);
            }
        }
    }
}
