// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseTestHooks} from "./BaseTestHooks.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {IHooks} from "../interfaces/IHooks.sol";

contract DynamicFeesTestHook is BaseTestHooks {
    uint24 internal fee;
    IPoolManager manager;

    function setManager(IPoolManager _manager) external {
        manager = _manager;
    }

    function setFee(uint24 _fee) external {
        fee = _fee;
    }

    function afterInitialize(address, PoolKey calldata key, uint160, int24, bytes calldata)
        external
        override
        returns (bytes4)
    {
        manager.updateDynamicLPFee(key, fee);
        return IHooks.afterInitialize.selector;
    }

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata)
        external
        override
        returns (bytes4, int128)
    {
        manager.updateDynamicLPFee(key, fee);
        return (IHooks.beforeSwap.selector, 0);
    }

    function forcePoolFeeUpdate(PoolKey calldata _key, uint24 _fee) external {
        manager.updateDynamicLPFee(_key, _fee);
    }
}
