// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {IERC20Minimal} from '../interfaces/external/IERC20Minimal.sol';

import {ILockCallback} from '../interfaces/callback/ILockCallback.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';
import {TWAMM} from '../libraries/TWAMM/TWAMM.sol';

contract PoolTWAMMTest is ILockCallback {
    IPoolManager public immutable manager;

    enum TransactionType {
        SUBMIT,
        EXECUTE
    }

    struct CallbackData {
        IPoolManager.PoolKey key;
        TransactionType txType;
        bytes params;
    }

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    function submitLongTermOrder(IPoolManager.PoolKey calldata key, TWAMM.LongTermOrderParams calldata params)
        external
        returns (uint256 orderId)
    {
        orderId = abi.decode(
            manager.lock(abi.encode(CallbackData(key, TransactionType.SUBMIT, abi.encode(params)))),
            (uint256)
        );
    }

    function executeTWAMMOrders(IPoolManager.PoolKey calldata key)
        external
        returns (IPoolManager.BalanceDelta memory delta)
    {
        delta = abi.decode(
            manager.lock(abi.encode(CallbackData(key, TransactionType.EXECUTE, abi.encode('')))),
            (IPoolManager.BalanceDelta)
        );
    }

    function lockAcquired(bytes calldata rawData) external returns (bytes memory returnVal) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        if (data.txType == TransactionType.SUBMIT) {
            TWAMM.LongTermOrderParams memory params = abi.decode(data.params, (TWAMM.LongTermOrderParams));
            returnVal = abi.encode(manager.submitLongTermOrder(data.key, params));
        } else if (data.txType == TransactionType.EXECUTE) {
            returnVal = abi.encode(manager.executeTWAMMOrders(data.key));
        }
    }
}
