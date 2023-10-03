// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Currency, CurrencyLibrary} from "../types/Currency.sol";
import {IERC20Minimal} from "../interfaces/external/IERC20Minimal.sol";

import {Currency} from "../types/Currency.sol";
import {ILockCallback} from "../interfaces/callback/ILockCallback.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";

contract PoolDonateTest is ILockCallback {
    using CurrencyLibrary for Currency;

    IPoolManager public immutable manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    struct CallbackData {
        address sender;
        PoolKey key;
        uint256 amount0;
        uint256 amount1;
        bytes hookData;
    }

    function donate(PoolKey memory key, uint256 amount0, uint256 amount1, bytes memory hookData)
        external
        payable
        returns (BalanceDelta delta)
    {
        delta = abi.decode(
            manager.lock(abi.encode(CallbackData(msg.sender, key, amount0, amount1, hookData))), (BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    function lockAcquired(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        BalanceDelta delta = manager.donate(data.key, data.amount0, data.amount1, data.hookData);

        if (delta.amount0() > 0) {
            if (data.key.currency0.isNative()) {
                manager.settle{value: uint128(delta.amount0())}(data.key.currency0);
            } else {
                IERC20Minimal(Currency.unwrap(data.key.currency0)).transferFrom(
                    data.sender, address(manager), uint128(delta.amount0())
                );
                manager.settle(data.key.currency0);
            }
        }
        if (delta.amount1() > 0) {
            if (data.key.currency1.isNative()) {
                manager.settle{value: uint128(delta.amount1())}(data.key.currency1);
            } else {
                IERC20Minimal(Currency.unwrap(data.key.currency1)).transferFrom(
                    data.sender, address(manager), uint128(delta.amount1())
                );
                manager.settle(data.key.currency1);
            }
        }

        return abi.encode(delta);
    }
}
