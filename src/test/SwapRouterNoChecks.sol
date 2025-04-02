// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Currency} from "../types/Currency.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {SwapParams} from "../types/PoolOperation.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {Hooks} from "../libraries/Hooks.sol";
import {PoolTestBase} from "./PoolTestBase.sol";
import {CurrencySettler} from "../../test/utils/CurrencySettler.sol";

contract SwapRouterNoChecks is PoolTestBase {
    using CurrencySettler for Currency;
    using Hooks for IHooks;

    constructor(IPoolManager _manager) PoolTestBase(_manager) {}

    error NoSwapOccurred();

    struct CallbackData {
        address sender;
        PoolKey key;
        SwapParams params;
    }

    function swap(PoolKey memory key, SwapParams memory params) external payable {
        manager.unlock(abi.encode(CallbackData(msg.sender, key, params)));
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        BalanceDelta delta = manager.swap(data.key, data.params, new bytes(0));

        if (data.params.zeroForOne) {
            data.key.currency0.settle(manager, data.sender, uint256(int256(-delta.amount0())), false);
            data.key.currency1.take(manager, data.sender, uint256(int256(delta.amount1())), false);
        } else {
            data.key.currency1.settle(manager, data.sender, uint256(int256(-delta.amount1())), false);
            data.key.currency0.take(manager, data.sender, uint256(int256(delta.amount0())), false);
        }

        return "";
    }
}
