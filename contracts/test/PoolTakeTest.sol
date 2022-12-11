// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {Currency, CurrencyLibrary} from '../libraries/CurrencyLibrary.sol';
import {CurrencyDelta} from '../libraries/CurrencyDelta.sol';
import {IERC20Minimal} from '../interfaces/external/IERC20Minimal.sol';

import {IExecuteCallback} from '../interfaces/callback/IExecuteCallback.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';

contract PoolTakeTest is IExecuteCallback {
    using CurrencyLibrary for Currency;

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
    ) external payable {
        bytes memory commands = new bytes(1);
        commands[0] = bytes1(uint8(IPoolManager.Command.TAKE));
        bytes[] memory inputs = new bytes[](1);
        if (amount0 > 0) {
            inputs[0] = abi.encode(key.currency0, msg.sender, amount0);
        } else if (amount1 > 0) {
            inputs[0] = abi.encode(key.currency1, msg.sender, amount1);
        }

        manager.execute(commands, inputs, abi.encode(CallbackData(msg.sender, key, amount0, amount1)));
    }

    function balanceOf(Currency currency, address user) internal view returns (uint256) {
        if (currency.isNative()) {
            return user.balance;
        } else {
            return IERC20Minimal(Currency.unwrap(currency)).balanceOf(user);
        }
    }

    function executeCallback(CurrencyDelta[] memory deltas, bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));
        for (uint256 i = 0; i < deltas.length; i++) {
            CurrencyDelta memory delta = deltas[i];
            if (delta.delta > 0) {
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

        return abi.encode(0);
    }
}
