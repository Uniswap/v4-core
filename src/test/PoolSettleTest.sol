// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Currency, CurrencyLibrary} from "../types/Currency.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {PoolTestBase} from "./PoolTestBase.sol";
import {SafeCast} from "../libraries/SafeCast.sol";

contract PoolSettleTest is PoolTestBase {
    using CurrencyLibrary for Currency;
    using SafeCast for uint256;

    constructor(IPoolManager _manager) PoolTestBase(_manager) {}

    struct CallbackData {
        address sender;
        PoolKey key;
        uint256 amount0;
        uint256 amount1;
    }

    function settle(PoolKey memory key, uint256 amount0, uint256 amount1) external payable {
        manager.unlock(abi.encode(CallbackData(msg.sender, key, amount0, amount1)));
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));
        manager.settle{value: address(this).balance}(data.key.currency0);

        return abi.encode(0);
    }
}
