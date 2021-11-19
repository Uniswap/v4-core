// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.10;

import {IERC20Minimal} from '../interfaces/external/IERC20Minimal.sol';

import {ILockCallback} from '../interfaces/callback/ILockCallback.sol';
import {ISettleCallback} from '../interfaces/callback/ISettleCallback.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';

import {Pool} from '../libraries/Pool.sol';

contract PoolSwapTest is ILockCallback, ISettleCallback {
    IPoolManager public immutable manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    struct CallbackData {
        address sender;
        IPoolManager.PoolKey key;
        IPoolManager.SwapParams params;
    }

    function swap(IPoolManager.PoolKey memory key, IPoolManager.SwapParams memory params)
        external
        returns (Pool.BalanceDelta memory delta)
    {
        delta = abi.decode(manager.lock(abi.encode(CallbackData(msg.sender, key, params))), (Pool.BalanceDelta));
    }

    function lockAcquired(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        Pool.BalanceDelta memory delta = manager.swap(data.key, data.params);

        manager.settle(data.key.token0, abi.encode(data.sender));
        manager.settle(data.key.token1, abi.encode(data.sender));

        return abi.encode(delta);
    }

    function settleCallback(
        IERC20Minimal token,
        int256 delta,
        bytes calldata data
    ) external override {
        require(msg.sender == address(manager));

        address sender = abi.decode(data, (address));

        if (delta > 0) {
            token.transferFrom(sender, msg.sender, uint256(delta));
        }
    }
}
