// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {CurrencyLibrary, Currency} from "../types/Currency.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {TakeAndSettler} from "./TakeAndSettler.sol";

contract PoolModifyPositionTest is TakeAndSettler {
    using CurrencyLibrary for Currency;

    constructor(IPoolManager _manager) TakeAndSettler(_manager) {}

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

        // Either both currencies need to be settled, or both need to be taken
        if (delta.amount0() > 0) _settle(data.key.currency0, data.sender, delta.amount0(), true);
        else if (delta.amount0() < 0) _take(data.key.currency0, data.sender, delta.amount0(), true);

        if (delta.amount1() > 0) _settle(data.key.currency1, data.sender, delta.amount1(), true);
        else if (delta.amount1() < 0) _take(data.key.currency1, data.sender, delta.amount1(), true);

        return abi.encode(delta);
    }
}
