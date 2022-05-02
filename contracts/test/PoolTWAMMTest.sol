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
        CLAIM,
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
        returns (bytes32 orderId)
    {
        orderId = abi.decode(
            manager.lock(abi.encode(CallbackData(key, TransactionType.SUBMIT, abi.encode(params)))),
            (bytes32)
        );
    }

    function claimEarningsOnLongTermOrder(IPoolManager.PoolKey calldata key, TWAMM.OrderKey calldata params)
        external
        returns (uint256 earningsAmount)
    {
        earningsAmount = abi.decode(
            manager.lock(abi.encode(CallbackData(key, TransactionType.CLAIM, abi.encode(params)))),
            (uint256)
        );
    }

    function executeTWAMMOrders(IPoolManager.PoolKey calldata key) external {
        manager.lock(abi.encode(CallbackData(key, TransactionType.EXECUTE, abi.encode(''))));
    }

    function lockAcquired(bytes calldata rawData) external returns (bytes memory returnVal) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        if (data.txType == TransactionType.SUBMIT) {
            TWAMM.LongTermOrderParams memory params = abi.decode(data.params, (TWAMM.LongTermOrderParams));
            returnVal = abi.encode(manager.submitLongTermOrder(data.key, params));
            IERC20Minimal token = params.zeroForOne ? data.key.token0 : data.key.token1;
            token.transferFrom(params.owner, address(manager), params.amountIn);
            manager.settle(token);
        } else if (data.txType == TransactionType.CLAIM) {
            TWAMM.OrderKey memory orderKey = abi.decode(data.params, (TWAMM.OrderKey));
            uint256 earnings = manager.claimEarningsOnLongTermOrder(data.key, orderKey);
            returnVal = abi.encode(earnings);
            IERC20Minimal token = orderKey.zeroForOne ? data.key.token1 : data.key.token0;
            manager.take(token, orderKey.owner, earnings);
        } else if (data.txType == TransactionType.EXECUTE) {
            manager.executeTWAMMOrders(data.key);
        }
    }
}
