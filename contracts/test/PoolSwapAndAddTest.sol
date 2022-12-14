// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {CurrencyDelta} from '../libraries/CurrencyDelta.sol';
import {CurrencyLibrary, Currency} from '../libraries/CurrencyLibrary.sol';
import {Commands} from '../libraries/Commands.sol';
import {IERC20Minimal} from '../interfaces/external/IERC20Minimal.sol';

import {IExecuteCallback} from '../interfaces/callback/IExecuteCallback.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';

contract PoolSwapAndAddTest is IExecuteCallback {
    using CurrencyLibrary for Currency;

    IPoolManager public immutable manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    struct CallbackData {
        address sender;
    }

    function swapAndAdd(
        IPoolManager.PoolKey memory key,
        IPoolManager.ModifyPositionParams memory params,
        bool zeroForOne,
        uint160 sqrtPriceLimit
    ) external payable returns (IPoolManager.BalanceDelta memory delta) {
        bytes memory commands = new bytes(2);
        commands[0] = Commands.MODIFY;
        commands[1] = Commands.SWAP;
        bytes[] memory inputs = new bytes[](2);
        inputs[0] = abi.encode(key, params);
        inputs[1] = abi.encode(
            key,
            IPoolManager.SwapParams(zeroForOne, Commands.EXACT_OUTPUT_ABS_DELTA, sqrtPriceLimit)
        );

        delta = abi.decode(manager.execute(commands, inputs, abi.encode(msg.sender)), (IPoolManager.BalanceDelta));

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    function executeCallback(CurrencyDelta[] memory deltas, bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        IPoolManager.BalanceDelta memory result;
        address sender = abi.decode(rawData, (address));

        for (uint256 i = 0; i < deltas.length; i++) {
            CurrencyDelta memory delta = deltas[i];
            if (i == 0) {
                result.amount0 = delta.delta;
            } else if (i == 1) {
                result.amount1 = delta.delta;
            }

            if (delta.delta > 0) {
                if (delta.currency.isNative()) {
                    payable(address(manager)).transfer(uint256(delta.delta));
                } else {
                    IERC20Minimal(Currency.unwrap(delta.currency)).transferFrom(
                        sender,
                        address(manager),
                        uint256(delta.delta)
                    );
                }
            }
        }

        return abi.encode(result);
    }
}
