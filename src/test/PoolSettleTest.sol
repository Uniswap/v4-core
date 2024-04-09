// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {PoolTestBase} from "./PoolTestBase.sol";

contract PoolSettleTest is PoolTestBase {
    constructor(IPoolManager _manager) PoolTestBase(_manager) {}

    struct CallbackData {
        address sender;
        PoolKey key;
    }

    function settle(PoolKey memory key) external payable {
        manager.unlock(abi.encode(CallbackData(msg.sender, key)));
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));
        manager.settle{value: address(this).balance}(data.key.currency0);

        return abi.encode(0);
    }
}
