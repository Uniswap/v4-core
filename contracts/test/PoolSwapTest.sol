// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {CurrencyDelta} from '../libraries/CurrencyDelta.sol';
import {CurrencyLibrary, Currency} from '../libraries/CurrencyLibrary.sol';
import {Commands} from '../libraries/Commands.sol';
import {IERC20Minimal} from '../interfaces/external/IERC20Minimal.sol';

import {IExecuteCallback} from '../interfaces/callback/IExecuteCallback.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';

contract PoolSwapTest is IExecuteCallback {
    using CurrencyLibrary for Currency;

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
    ) external payable returns (IPoolManager.BalanceDelta memory delta) {
        bytes memory commands = new bytes(2);
        commands[0] = Commands.SWAP;
        if (testSettings.withdrawTokens) {
            commands[1] = Commands.TAKE;
        } else {
            commands[1] = Commands.MINT;
        }
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(key, params);
        if (params.zeroForOne) {
            inputs[1] = abi.encode(key.currency1, msg.sender, 0);
        } else {
            inputs[1] = abi.encode(key.currency0, msg.sender, 0);
        }

        delta = abi.decode(
            manager.execute(commands, inputs, abi.encode(CallbackData(msg.sender, testSettings, key, params))),
            (IPoolManager.BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    function executeCallback(CurrencyDelta[] memory deltas, bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));
        IPoolManager.BalanceDelta memory result;

        for (uint256 i = 0; i < deltas.length; i++) {
            CurrencyDelta memory delta = deltas[i];
            if (i == 0) {
                result.amount0 = delta.delta;
            } else if (i == 1) {
                result.amount1 = delta.delta;
            }

            if (data.testSettings.settleUsingTransfer && delta.delta > 0) {
                if (delta.currency.isNative()) {
                    payable(address(manager)).transfer(uint256(delta.delta));
                } else {
                    IERC20Minimal(Currency.unwrap(delta.currency)).transferFrom(
                        data.sender,
                        address(manager),
                        uint256(delta.delta)
                    );
                }
            }
        }

        return abi.encode(result);
    }
}
