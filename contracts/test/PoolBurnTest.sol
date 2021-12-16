// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.10;

import {IERC20Minimal} from '../interfaces/external/IERC20Minimal.sol';

import {ILockCallback} from '../interfaces/callback/ILockCallback.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';
import {IV3PoolImplementation} from '../interfaces/implementations/IV3PoolImplementation.sol';
import {BalanceDelta} from '../interfaces/shared.sol';

import {Pool} from '../libraries/Pool.sol';

contract PoolBurnTest is ILockCallback {
    IPoolManager public immutable manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    struct CallbackData {
        address sender;
        IPoolManager.PoolKey key;
        IV3PoolImplementation.BurnParams params;
    }

    function burn(IPoolManager.PoolKey memory key, IV3PoolImplementation.BurnParams memory params)
        external
        returns (BalanceDelta memory delta)
    {
        delta = abi.decode(manager.lock(abi.encode(CallbackData(msg.sender, key, params))), (Pool.BalanceDelta));
    }

    function lockAcquired(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        BalanceDelta memory delta = manager.burn(data.key, data.params);

        if (delta.amount0 < 0) {
            manager.take(data.key.token0, data.sender, uint256(-delta.amount0));
        }
        if (delta.amount1 < 0) {
            manager.take(data.key.token1, data.sender, uint256(-delta.amount1));
        }

        return abi.encode(delta);
    }
}
