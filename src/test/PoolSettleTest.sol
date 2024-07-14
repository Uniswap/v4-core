// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {PoolTestBase} from "./PoolTestBase.sol";

contract PoolSettleTest is PoolTestBase {
    constructor(IPoolManager _manager) PoolTestBase(_manager) {}

    function settle() external payable {
        manager.unlock("");
    }

    function unlockCallback(bytes calldata) external returns (bytes memory) {
        require(msg.sender == address(manager));

        manager.settle{value: address(this).balance}();

        return abi.encode(0);
    }
}
