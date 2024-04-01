// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {CurrencyLibrary, Currency} from "../types/Currency.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../types/BalanceDelta.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {PoolTestBase} from "./PoolTestBase.sol";
import {Hooks} from "../libraries/Hooks.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {IERC20Minimal} from "../interfaces/external/IERC20Minimal.sol";

contract PoolSwapTestGas {
    using CurrencyLibrary for Currency;
    using Hooks for IHooks;

    IPoolManager public immutable manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    struct CallbackData {
        address sender;
        PoolKey key;
        IPoolManager.SwapParams params;
    }

    function swap(PoolKey memory key, IPoolManager.SwapParams memory params) external payable {
        abi.decode(manager.unlock(abi.encode(CallbackData(msg.sender, key, params))), (BalanceDelta));
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        BalanceDelta delta = manager.swap(data.key, data.params, "");

        int128 delta0 = delta.amount0();
        int128 delta1 = delta.amount1();

        if (delta0 < 0) {
            _settle(data.key.currency0, data.sender, uint128(-delta0));
        } else if (delta0 > 0) {
            manager.take(data.key.currency0, data.sender, uint128(delta0));
        }
        if (delta1 < 0) {
            _settle(data.key.currency1, data.sender, uint128(-delta1));
        } else if (delta1 > 0) {
            manager.take(data.key.currency1, data.sender, uint128(delta1));
        }

        return abi.encode(delta);
    }

    function _settle(Currency currency, address payer, uint128 amount) internal {
        if (currency.isNative()) {
            manager.settle{value: amount}(currency);
        } else {
            IERC20Minimal(Currency.unwrap(currency)).transferFrom(payer, address(manager), amount);
            manager.settle(currency);
        }
    }
}
