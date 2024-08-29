// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {Currency} from "../types/Currency.sol";
import {PoolTestBase} from "./PoolTestBase.sol";

contract PoolSettleTest is PoolTestBase {
    constructor(IPoolManager _manager) PoolTestBase(_manager) {}

    function settle(Currency syncCurrency) external payable {
        manager.unlock(abi.encode(syncCurrency));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(manager));

        Currency syncCurrency = abi.decode(data, (Currency));
        manager.sync(syncCurrency);

        manager.settle{value: address(this).balance}();

        return abi.encode(0);
    }
}
