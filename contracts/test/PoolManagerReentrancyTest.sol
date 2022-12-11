// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {Currency, CurrencyLibrary} from '../libraries/CurrencyLibrary.sol';
import {CurrencyDelta} from '../libraries/CurrencyDelta.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';
import {IExecuteCallback} from '../interfaces/callback/IExecuteCallback.sol';

contract PoolManagerReentrancyTest is IExecuteCallback {
    using CurrencyLibrary for Currency;

    function reenter(
        IPoolManager poolManager,
        Currency currencyToBorrow,
        uint256 count
    ) external {
        helper(poolManager, currencyToBorrow, count, count);
    }

    function helper(
        IPoolManager poolManager,
        Currency currencyToBorrow,
        uint256 total,
        uint256 count
    ) internal {
        IPoolManager.Command[] memory commands = new IPoolManager.Command[](1);
        commands[0] = IPoolManager.Command.TAKE;
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(currencyToBorrow, address(this), 1);
        poolManager.execute(abi.encode(commands), inputs, abi.encode(currencyToBorrow, total, count));
    }

    function executeCallback(CurrencyDelta[] memory deltas, bytes calldata data) external returns (bytes memory) {
        (Currency currencyToBorrow, uint256 total, uint256 count) = abi.decode(data, (Currency, uint256, uint256));

        IPoolManager poolManager = IPoolManager(msg.sender);

        // then pay it back
        currencyToBorrow.transfer(address(poolManager), 1);

        helper(IPoolManager(msg.sender), currencyToBorrow, total, count - 1);

        return '';
    }
}
