// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Currency, CurrencyLibrary} from "../types/Currency.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {TakeAndSettler} from "./TakeAndSettler.sol";
import {SafeCast} from "../libraries/SafeCast.sol";

contract PoolTakeTest is TakeAndSettler {
    using CurrencyLibrary for Currency;
    using SafeCast for uint256;

    constructor(IPoolManager _manager) TakeAndSettler(_manager) {}

    struct CallbackData {
        address sender;
        PoolKey key;
        uint256 amount0;
        uint256 amount1;
    }

    function take(PoolKey memory key, uint256 amount0, uint256 amount1) external payable {
        manager.lock(abi.encode(CallbackData(msg.sender, key, amount0, amount1)));
    }

    function lockAcquired(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        if (data.amount0 > 0) {
            uint256 balBefore = data.key.currency0.balanceOf(data.sender);
            _take(data.key.currency0, data.sender, -data.amount0.toInt128(), true);
            uint256 balAfter = data.key.currency0.balanceOf(data.sender);
            require(balAfter - balBefore == data.amount0);

            _settle(data.key.currency0, data.sender, data.amount0.toInt128(), true);
        }

        if (data.amount1 > 0) {
            uint256 balBefore = data.key.currency1.balanceOf(data.sender);
            _take(data.key.currency1, data.sender, -data.amount1.toInt128(), true);
            uint256 balAfter = data.key.currency1.balanceOf(data.sender);
            require(balAfter - balBefore == data.amount1);

            _settle(data.key.currency1, data.sender, data.amount1.toInt128(), true);
        }

        return abi.encode(0);
    }
}
