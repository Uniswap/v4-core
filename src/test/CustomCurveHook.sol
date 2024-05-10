// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Hooks} from "../libraries/Hooks.sol";
import {SafeCast} from "../libraries/SafeCast.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta, toBalanceDelta} from "../types/BalanceDelta.sol";
import {Currency} from "../types/Currency.sol";
import {CurrencySettleTake} from "../libraries/CurrencySettleTake.sol";
import {BaseTestHooks} from "./BaseTestHooks.sol";
import {IERC20Minimal} from "../interfaces/external/IERC20Minimal.sol";
import {CurrencyLibrary, Currency} from "../types/Currency.sol";

contract CustomCurveHook is BaseTestHooks {
    using Hooks for IHooks;
    using CurrencyLibrary for Currency;
    using CurrencySettleTake for Currency;

    error AddLiquidityDirectToHook();

    IPoolManager immutable manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    modifier onlyPoolManager() {
        require(msg.sender == address(manager));
        _;
    }

    function beforeSwap(
        address, /* sender **/
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata /* hookData **/
    ) external override onlyPoolManager returns (bytes4, int128) {
        (Currency inputCurrency, Currency outputCurrency, uint256 amount) = _getInputOutputAndAmount(key, params);

        // this "custom curve" is a line, 1-1
        // take the full input amount, and give the full output amount
        manager.take(inputCurrency, address(this), amount);
        outputCurrency.settle(manager, address(this), amount, false);

        // return -amountSpecified to no-op the concentrated liquidity swap
        return (IHooks.beforeSwap.selector, int128(-params.amountSpecified));
    }

    function afterSwap(
        address, /* sender **/
        PoolKey calldata, /* key **/
        IPoolManager.SwapParams calldata params,
        BalanceDelta, /* delta **/
        bytes calldata /* hookData **/
    ) external view override onlyPoolManager returns (bytes4, int128) {
        return (IHooks.afterSwap.selector, int128(params.amountSpecified));
    }

    function afterAddLiquidity(
        address, /* sender **/
        PoolKey calldata, /* key **/
        IPoolManager.ModifyLiquidityParams calldata, /* params **/
        BalanceDelta, /* delta **/
        bytes calldata /* hookData **/
    ) external view override onlyPoolManager returns (bytes4, BalanceDelta) {
        revert AddLiquidityDirectToHook();
    }

    function _getInputOutputAndAmount(PoolKey calldata key, IPoolManager.SwapParams calldata params)
        internal
        pure
        returns (Currency input, Currency output, uint256 amount)
    {
        (input, output) = params.zeroForOne ? (key.currency0, key.currency1) : (key.currency1, key.currency0);

        amount = params.amountSpecified < 0 ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);
    }
}
