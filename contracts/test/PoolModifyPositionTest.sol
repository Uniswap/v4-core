// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {IERC20Minimal} from '../interfaces/external/IERC20Minimal.sol';

import {ILockCallback} from '../interfaces/callback/ILockCallback.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';

contract PoolModifyPositionTest is ILockCallback {
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
        returns (IPoolManager.BalanceDelta memory delta)
    {
        delta = abi.decode(
            manager.lock(abi.encode(CallbackData(msg.sender, key, params))),
            (IPoolManager.BalanceDelta)
        );
    }

    function lockAcquired(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        IPoolManager.BalanceDelta memory delta = manager.modifyPosition(data.key, data.params);

        if (delta.amount0 > 0) {
            data.key.token0.transferFrom(data.sender, address(manager), uint256(delta.amount0));
            manager.settle(data.key.token0);
        }
        if (delta.amount1 > 0) {
            data.key.token1.transferFrom(data.sender, address(manager), uint256(delta.amount1));
            manager.settle(data.key.token1);
        }

        return abi.encode(delta);
    }
}
