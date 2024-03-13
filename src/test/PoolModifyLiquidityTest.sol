// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {CurrencyLibrary, Currency} from "../types/Currency.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {PoolTestBase} from "./PoolTestBase.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {Hooks} from "../libraries/Hooks.sol";
import {Test} from "forge-std/Test.sol";
import {SwapFeeLibrary} from "../libraries/SwapFeeLibrary.sol";

contract PoolModifyLiquidityTest is Test, PoolTestBase {
    using CurrencyLibrary for Currency;
    using Hooks for IHooks;
    using SwapFeeLibrary for uint24;

    constructor(IPoolManager _manager) PoolTestBase(_manager) {}

    struct CallbackData {
        address sender;
        PoolKey key;
        IPoolManager.ModifyLiquidityParams params;
        bytes hookData;
        bool settleUsingTransfer;
        bool withdrawTokens;
    }

    function modifyLiquidity(
        PoolKey memory key,
        IPoolManager.ModifyLiquidityParams memory params,
        bytes memory hookData
    ) external payable returns (BalanceDelta delta) {
        delta = modifyLiquidity(key, params, hookData, true, true);
    }

    function modifyLiquidity(
        PoolKey memory key,
        IPoolManager.ModifyLiquidityParams memory params,
        bytes memory hookData,
        bool settleUsingTransfer,
        bool withdrawTokens
    ) public payable returns (BalanceDelta delta) {
        delta = abi.decode(
            manager.lock(
                abi.encode(CallbackData(msg.sender, key, params, hookData, settleUsingTransfer, withdrawTokens))
            ),
            (BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    function lockAcquired(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        BalanceDelta delta = manager.modifyLiquidity(data.key, data.params, data.hookData);

        (,,, int256 delta0) = _fetchBalances(data.key.currency0, data.sender, address(this));
        (,,, int256 delta1) = _fetchBalances(data.key.currency1, data.sender, address(this));

        if (data.params.liquidityDelta < 0) {
            assert(delta0 > 0 || delta1 > 0);
            assert(!(delta0 < 0 || delta1 < 0));
        } else if (data.params.liquidityDelta > 0) {
            assert(delta0 < 0 || delta1 < 0);
            assert(!(delta0 > 0 || delta1 > 0));
        }

        if (delta0 < 0) _settle(data.key.currency0, data.sender, int128(delta0), data.settleUsingTransfer);
        if (delta1 < 0) _settle(data.key.currency1, data.sender, int128(delta1), data.settleUsingTransfer);
        if (delta0 > 0) _take(data.key.currency0, data.sender, int128(delta0), data.withdrawTokens);
        if (delta1 > 0) _take(data.key.currency1, data.sender, int128(delta1), data.withdrawTokens);

        return abi.encode(delta);
    }
}
