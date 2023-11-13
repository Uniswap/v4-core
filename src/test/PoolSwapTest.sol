// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {CurrencyLibrary, Currency} from "../types/Currency.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {TakeAndSettler} from "./TakeAndSettler.sol";

contract PoolSwapTest is TakeAndSettler {
    using CurrencyLibrary for Currency;

    constructor(IPoolManager _manager) TakeAndSettler(_manager) {}

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

        // Make sure youve added liquidity to the test pool!
        if (BalanceDelta.unwrap(delta) == 0) revert NoSwapOccurred();

        if (data.params.zeroForOne) {
            _settle(data.key.currency0, data.sender, delta.amount0(), data.testSettings.settleUsingTransfer);
            _take(data.key.currency1, data.sender, delta.amount1(), data.testSettings.withdrawTokens);
        } else {
            _settle(data.key.currency1, data.sender, delta.amount1(), data.testSettings.settleUsingTransfer);
            _take(data.key.currency0, data.sender, delta.amount0(), data.testSettings.withdrawTokens);
        }

        return abi.encode(delta);
    }
}
