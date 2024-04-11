// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseTestHooks} from "./BaseTestHooks.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {IHooks} from "../interfaces/IHooks.sol";

contract DynamicReturnFeeTestHook is BaseTestHooks {
    uint24 internal fee;
    IPoolManager manager;

    function setManager(IPoolManager _manager) external {
        manager = _manager;
    }

    function setFee(uint24 _fee) external {
        fee = _fee;
    }

    function beforeSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, bytes calldata)
        external
        override
        returns (bytes4, int128, uint24)
    {
        return (IHooks.beforeSwap.selector, 0, fee);
    }
}
