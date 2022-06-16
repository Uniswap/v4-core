// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {IERC20Minimal} from '../interfaces/external/IERC20Minimal.sol';

import {ILockCallback} from '../interfaces/callback/ILockCallback.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';

contract PoolTakeTest is ILockCallback {
    IPoolManager public immutable manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    struct CallbackData {
        address sender;
        IPoolManager.PoolKey key;
        uint256 amount0;
        uint256 amount1;
    }

    function take(
        IPoolManager.PoolKey memory key,
        uint256 amount0,
        uint256 amount1
    ) external {
        manager.lock(abi.encode(CallbackData(msg.sender, key, amount0, amount1)));
    }

    function lockAcquired(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        if (data.amount0 > 0) {
            uint256 balBefore = data.key.token0.balanceOf(data.sender);
            manager.take(data.key.token0, data.sender, data.amount0);
            uint256 balAfter = data.key.token0.balanceOf(data.sender);
            require(balAfter - balBefore == data.amount0);

            data.key.token0.transferFrom(data.sender, address(manager), uint256(data.amount0));
            manager.settle(data.key.token0);
        }

        if (data.amount1 > 0) {
            uint256 balBefore = data.key.token1.balanceOf(data.sender);
            manager.take(data.key.token1, data.sender, data.amount1);
            uint256 balAfter = data.key.token1.balanceOf(data.sender);
            require(balAfter - balBefore == data.amount1);

            data.key.token1.transferFrom(data.sender, address(manager), uint256(data.amount1));
            manager.settle(data.key.token1);
        }

        return abi.encode(0);
    }
}
