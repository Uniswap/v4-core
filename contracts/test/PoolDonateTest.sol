// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {IERC20Minimal} from '../interfaces/external/IERC20Minimal.sol';

import {ILockCallback} from '../interfaces/callback/ILockCallback.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';

contract PoolDonateTest is ILockCallback {
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

    function donate(
        IPoolManager.PoolKey memory key,
        uint256 amount0,
        uint256 amount1
    ) external returns (IPoolManager.BalanceDelta memory delta) {
        delta = abi.decode(
            manager.lock(abi.encode(CallbackData(msg.sender, key, amount0, amount1))),
            (IPoolManager.BalanceDelta)
        );
    }

    function lockAcquired(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        IPoolManager.BalanceDelta memory delta = manager.donate(data.key, data.amount0, data.amount1);

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
