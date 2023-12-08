// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {CurrencyLibrary, Currency} from "../types/Currency.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {PoolTestBase} from "./PoolTestBase.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {Hooks} from "../libraries/Hooks.sol";
import {Test} from "forge-std/Test.sol";
import {FeeLibrary} from "../libraries/FeeLibrary.sol";

contract PoolModifyPositionTest is Test, PoolTestBase {
    using CurrencyLibrary for Currency;
    using Hooks for IHooks;
    using FeeLibrary for uint24;

    enum LockAction {
        AddLiquidity,
        RemoveLiquidity
    }

    constructor(IPoolManager _manager) PoolTestBase(_manager) {}

    struct CallbackData {
        address sender;
        PoolKey key;
        IPoolManager.ModifyPositionParams params;
        bytes hookData;
        LockAction action;
    }

    function removeLiquidity(PoolKey memory key, IPoolManager.ModifyPositionParams memory params, bytes memory hookData)
        external
        payable
        returns (BalanceDelta delta)
    {
        delta = _modifyPosition(key, params, hookData, LockAction.RemoveLiquidity);
    }

    function addLiquidity(PoolKey memory key, IPoolManager.ModifyPositionParams memory params, bytes memory hookData)
        external
        payable
        returns (BalanceDelta delta)
    {
        delta = _modifyPosition(key, params, hookData, LockAction.AddLiquidity);
    }

    function _modifyPosition(
        PoolKey memory key,
        IPoolManager.ModifyPositionParams memory params,
        bytes memory hookData,
        LockAction action
    ) internal returns (BalanceDelta delta) {
        delta = abi.decode(
            manager.lock(address(this), abi.encode(CallbackData(msg.sender, key, params, hookData, action))),
            (BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    function lockAcquired(address, bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        BalanceDelta delta;
        if (data.action == LockAction.AddLiquidity) {
            delta = manager.addLiquidity(data.key, data.params, data.hookData);
        } else {
            delta = manager.removeLiquidity(data.key, data.params, data.hookData);
        }

        // Checks that the current hook is cleared if there is an access lock. Note that if this router is ever used in a nested lock this will fail.
        assertEq(address(manager.getCurrentHook()), address(0));

        (,,, int256 delta0) = _fetchBalances(data.key.currency0, data.sender);
        (,,, int256 delta1) = _fetchBalances(data.key.currency1, data.sender);

        // These assertions only apply in non lock-accessing pools.
        if (!data.key.hooks.hasPermissionToAccessLock() && !data.key.fee.hasHookWithdrawFee()) {
            if (data.action == LockAction.AddLiquidity) {
                require(delta0 > 0 || delta1 > 0 || data.key.hooks.hasPermissionToNoOp(), "assert 1 failed");
                require(!(delta0 < 0 || delta1 < 0), "assert 2 failed");
            } else {
                require(delta0 < 0 || delta1 < 0 || data.key.hooks.hasPermissionToNoOp(), "assert 3 failed");
                require(!(delta0 > 0 || delta1 > 0), "assert 4 failed");
            }
        }

        if (delta0 > 0) _settle(data.key.currency0, data.sender, int128(delta0), true);
        if (delta1 > 0) _settle(data.key.currency1, data.sender, int128(delta1), true);
        if (delta0 < 0) _take(data.key.currency0, data.sender, int128(delta0), true);
        if (delta1 < 0) _take(data.key.currency1, data.sender, int128(delta1), true);

        return abi.encode(delta);
    }
}
