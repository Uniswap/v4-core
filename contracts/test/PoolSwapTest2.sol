// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {IERC20Minimal} from '../interfaces/external/IERC20Minimal.sol';

import {ILockCallback} from '../interfaces/callback/ILockCallback.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';

contract PoolSwapTest2 is ILockCallback {
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

        // Manually build calldata so we can add in hooksParams as a hidden param.
        bytes memory swapCalldata = abi.encodeWithSelector(IPoolManager.swap.selector, data.key, data.params);
        bytes memory swapCalldataWithHooksParams = bytes.concat(
            swapCalldata,
            abi.encodePacked(address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF))
        );

        (bool success, bytes memory returnData) = address(manager).call(swapCalldataWithHooksParams);

        if (!success || returnData.length == 0) {
            revert('Swap Failed');
        }

        IPoolManager.BalanceDelta memory delta = abi.decode(returnData, (IPoolManager.BalanceDelta));

        if (data.params.zeroForOne) {
            if (delta.amount0 > 0) {
                data.key.token0.transferFrom(data.sender, address(manager), uint256(delta.amount0));
                manager.settle(data.key.token0);
            }
            if (delta.amount1 < 0) manager.take(data.key.token1, data.sender, uint256(-delta.amount1));
        } else {
            if (delta.amount1 > 0) {
                data.key.token1.transferFrom(data.sender, address(manager), uint256(delta.amount1));
                manager.settle(data.key.token1);
            }
            if (delta.amount0 < 0) {
                manager.take(data.key.token0, data.sender, uint256(-delta.amount0));
            }
        }

        return abi.encode(delta);
    }
}
