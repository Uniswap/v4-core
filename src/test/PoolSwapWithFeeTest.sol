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
import {SafeCast} from "../libraries/SafeCast.sol";

contract PoolSwapWithFeeTest is Test, PoolTestBase {
    using CurrencyLibrary for Currency;
    using Hooks for IHooks;
    using SafeCast for uint256;
    using SafeCast for int256;

    constructor(IPoolManager _manager) PoolTestBase(_manager) {}

    uint256 public constant TOTAL_DEBT = uint256(0);

    error NoSwapOccurred();

    struct CallbackData {
        address sender;
        PoolKey key;
        IPoolManager.SwapParams params;
        uint256 minAmountOut;
    }

    function swapExactInput(PoolKey memory key, IPoolManager.SwapParams memory params, uint256 minAmountOut)
        external
        payable
        returns (BalanceDelta delta)
    {
        delta = abi.decode(
            manager.lock(address(this), abi.encode(CallbackData(msg.sender, key, params, minAmountOut))), (BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
    }

    function lockAcquired(address sender, bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));
        sender = (sender == address(this)) ? data.sender : sender;

        BalanceDelta delta = manager.swap(data.key, data.params, "");

        if (data.params.zeroForOne) {
            // settle input
            _settle(data.key.currency0, sender, delta.amount0(), true);

            // settle output and fee
            manager.settleFor(data.key.currency1, address(data.key.hooks), TOTAL_DEBT);
            int256 amountOut = manager.currencyDelta(address(this), data.key.currency1);
            require((-amountOut).toUint256() >= data.minAmountOut);
            _take(data.key.currency1, sender, amountOut.toInt128(), true);
        } else {
            // settle input
            _settle(data.key.currency1, sender, delta.amount1(), true);

            // settle output and fee
            manager.settleFor(data.key.currency0, address(data.key.hooks), TOTAL_DEBT);
            int256 amountOut = manager.currencyDelta(address(this), data.key.currency1);
            require((-amountOut).toUint256() >= data.minAmountOut);
            _take(data.key.currency0, sender, amountOut.toInt128(), true);
        }

        return abi.encode(delta);
    }
}
