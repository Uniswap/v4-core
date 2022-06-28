// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {CurrencyLibrary, Currency} from '../libraries/CurrencyLibrary.sol';
import {IERC20Minimal} from '../interfaces/external/IERC20Minimal.sol';

import {ILockCallback} from '../interfaces/callback/ILockCallback.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';

contract PoolModifyPositionTest is ILockCallback {
    using CurrencyLibrary for Currency;
    IPoolManager public immutable manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    struct CallbackData {
        address sender;
        IPoolManager.PoolKey key;
        IPoolManager.ModifyPositionParams params;
    }

    function modifyPosition(IPoolManager.PoolKey memory key, IPoolManager.ModifyPositionParams memory params)
        external
        payable
        returns (IPoolManager.BalanceDelta memory delta)
    {
        delta = abi.decode(
            manager.lock(abi.encode(CallbackData(msg.sender, key, params))),
            (IPoolManager.BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    function lockAcquired(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        IPoolManager.BalanceDelta memory delta = manager.modifyPosition(data.key, data.params);

        if (delta.amount0 > 0) {
            if (data.key.currency0.isNative()) {
                manager.settle{value: uint256(delta.amount0)}(data.key.currency0);
            } else {
                IERC20Minimal(Currency.unwrap(data.key.currency0)).transferFrom(
                    data.sender,
                    address(manager),
                    uint256(delta.amount0)
                );
                manager.settle(data.key.currency0);
            }
        }
        if (delta.amount1 > 0) {
            if (data.key.currency1.isNative()) {
                manager.settle{value: uint256(delta.amount1)}(data.key.currency1);
            } else {
                IERC20Minimal(Currency.unwrap(data.key.currency1)).transferFrom(
                    data.sender,
                    address(manager),
                    uint256(delta.amount1)
                );
                manager.settle(data.key.currency1);
            }
        }

        return abi.encode(delta);
    }
}
