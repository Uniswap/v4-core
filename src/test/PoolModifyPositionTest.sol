// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {CurrencyLibrary, Currency} from "../types/Currency.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {PoolTestBase} from "./PoolTestBase.sol";

contract PoolModifyPositionTest is PoolTestBase {
    using CurrencyLibrary for Currency;

    constructor(IPoolManager _manager) PoolTestBase(_manager) {}

    struct CallbackData {
        address sender;
        PoolKey key;
        IPoolManager.ModifyPositionParams params;
        bytes hookData;
    }

    function modifyPosition(PoolKey memory key, IPoolManager.ModifyPositionParams memory params, bytes memory hookData)
        external
        payable
        returns (BalanceDelta delta)
    {
        delta = abi.decode(manager.lock(abi.encode(CallbackData(msg.sender, key, params, hookData))), (BalanceDelta));

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    function lockAcquired(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        BalanceDelta delta = manager.modifyPosition(data.key, data.params, data.hookData);

        (,,, int256 delta0) = _fetchBalances(data.key.currency0, data.sender);
        (,,, int256 delta1) = _fetchBalances(data.key.currency1, data.sender);

        if (data.params.liquidityDelta > 0) {
            assert(delta0 > 0 || delta1 > 0);
            assert(!(delta0 < 0 || delta1 < 0));
            if (delta0 > 0) _settle(data.key.currency0, data.sender, delta.amount0(), true);
            if (delta1 > 0) _settle(data.key.currency1, data.sender, delta.amount1(), true);
        } else {
            assert(delta0 < 0 || delta1 < 0);
            assert(!(delta0 > 0 || delta1 > 0));
            if (delta0 < 0) _take(data.key.currency0, data.sender, delta.amount0(), true);
            if (delta1 < 0) _take(data.key.currency1, data.sender, delta.amount1(), true);
        }

        return abi.encode(delta);
    }
}
