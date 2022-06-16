// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {IERC20Minimal} from '../interfaces/external/IERC20Minimal.sol';

import {ILockCallback} from '../interfaces/callback/ILockCallback.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';

contract PoolSwapTest is ILockCallback {
    IPoolManager public immutable manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    struct CallbackData {
        address sender;
        TestSettings testSettings;
        IPoolManager.PoolKey key;
        IPoolManager.SwapParams params;
    }

    struct TestSettings {
        bool withdrawTokens;
        bool settleUsingTransfer;
    }

    function swap(
        IPoolManager.PoolKey memory key,
        IPoolManager.SwapParams memory params,
        TestSettings memory testSettings
    ) external returns (IPoolManager.BalanceDelta memory delta) {
        delta = abi.decode(
            manager.lock(abi.encode(CallbackData(msg.sender, testSettings, key, params))),
            (IPoolManager.BalanceDelta)
        );
    }

    function lockAcquired(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        IPoolManager.BalanceDelta memory delta = manager.swap(data.key, data.params);

        if (data.params.zeroForOne) {
            if (delta.amount0 > 0) {
                if (data.testSettings.settleUsingTransfer) {
                    data.key.token0.transferFrom(data.sender, address(manager), uint256(delta.amount0));
                    manager.settle(data.key.token0);
                } else {
                    // the received hook on this transfer will burn the tokens
                    manager.safeTransferFrom(
                        data.sender,
                        address(manager),
                        uint256(uint160(address((data.key.token0)))),
                        uint256(delta.amount0),
                        ''
                    );
                }
            }
            if (delta.amount1 < 0) {
                if (data.testSettings.withdrawTokens)
                    manager.take(data.key.token1, data.sender, uint256(-delta.amount1));
                else manager.mint(data.key.token1, data.sender, uint256(-delta.amount1));
            }
        } else {
            if (delta.amount1 > 0) {
                if (data.testSettings.settleUsingTransfer) {
                    data.key.token1.transferFrom(data.sender, address(manager), uint256(delta.amount1));
                    manager.settle(data.key.token1);
                } else {
                    // the received hook on this transfer will burn the tokens
                    manager.safeTransferFrom(
                        data.sender,
                        address(manager),
                        uint256(uint160(address((data.key.token1)))),
                        uint256(delta.amount1),
                        ''
                    );
                }
            }
            if (delta.amount0 < 0) {
                if (data.testSettings.withdrawTokens)
                    manager.take(data.key.token0, data.sender, uint256(-delta.amount0));
                else manager.mint(data.key.token0, data.sender, uint256(-delta.amount0));
            }
        }

        return abi.encode(delta);
    }
}
