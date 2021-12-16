// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.10;

import {IERC20Minimal} from '../interfaces/external/IERC20Minimal.sol';

import {ILockCallback} from '../interfaces/callback/ILockCallback.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';

import {Pool} from '../libraries/Pool.sol';
import {IV3PoolImplementation} from '../interfaces/implementations/IV3PoolImplementation.sol';
import {BalanceDelta} from '../interfaces/shared.sol';

contract PoolModifyPositionTest is ILockCallback {
    IPoolManager public immutable manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    struct CallbackData {
        address sender;
        IPoolManager.PoolKey key;
        IV3PoolImplementation.ModifyPositionParams params;
    }

    function mint(IPoolManager.PoolKey memory key, IV3PoolImplementation.ModifyPositionParams memory params)
        external
        returns (BalanceDelta memory delta)
    {
        delta = abi.decode(manager.lock(abi.encode(CallbackData(msg.sender, key, params))), (BalanceDelta));
    }

    function lockAcquired(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        BalanceDelta memory delta = manager.modifyPosition(data.key, abi.encode(data.params));

        if (delta.amount0 > 0) {
            data.key.pair.token0.transferFrom(data.sender, address(manager), uint256(delta.amount0));
            manager.settle(data.key.pair.token0);
        }
        if (delta.amount1 > 0) {
            data.key.pair.token1.transferFrom(data.sender, address(manager), uint256(delta.amount1));
            manager.settle(data.key.pair.token1);
        }

        return abi.encode(delta);
    }
}
