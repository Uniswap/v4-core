// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

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
        PoolKey key;
        IPoolManager.SwapParams params;
        bool hookTakesFee;
    }

    function swap(
        PoolKey memory key,
        IPoolManager.SwapParams memory params,
        bool hookTakesFee
    ) external payable returns (BalanceDelta delta) {
        delta = abi.decode(
            manager.lock(address(this), abi.encode(CallbackData(msg.sender, key, params, hookTakesFee))),
            (BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
    }

    function lockAcquired(address sender, bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));
        sender = (sender == address(this)) ? data.sender : sender;

        BalanceDelta delta = manager.swap(data.key, data.params, "");

        // We can return as we dont need to settle
        if (delta == BalanceDeltaLibrary.MAXIMUM_DELTA) return abi.encode(delta);

        if (zeroForOne) {
            _settle(data.current0, sender, delta.amount0(), true);
            if (hookTakesFee) _settleFee(data.key.currency1, );

        } else {
            _take(data.key.currency0, sender, delta.amount0(), true);
            _settle(data.key.currency1, sender, delta.amount1(), true);
            if (data.hookTakesFee) {
                int256 amountOutFee = manager.currencyDelta(address(data.key.hooks), data.key.currency0);
                if (amountOutFee > 0) _settle(data.key.currency0, sender, address(data.key.hooks), amountOutFee, true);
            }
        }

        return abi.encode(delta);
    }

    function _settleWithFee(Currency currency, address payer, int128 amountOut, PoolKey key) internal {
        int256 amountOutFee = manager.currencyDelta(address(key.hooks), currency);
        uint256 amountToTransfer = (amountOutFee > 0) ? amountOut + amountOutFee : amountOut;

        IERC20Minimal(Currency.unwrap(currency)).transferFrom(payer, address(manager), uint128(amountOut));
        (amountOutFee > 0) ? manager.settleForTarget(currency, address(key.hooks), amountOutFee);
        manager.settle(currency);
}