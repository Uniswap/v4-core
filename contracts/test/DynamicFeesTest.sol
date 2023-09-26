// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTestHooks} from "./BaseTestHooks.sol";
import {IDynamicFeeManager} from "../interfaces/IDynamicFeeManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {IHooks} from "../interfaces/IHooks.sol";

contract DynamicFeesTest is BaseTestHooks, IDynamicFeeManager {
    uint24 internal fee;
    IPoolManager manager;

    constructor() {}

    function setManager(IPoolManager _manager) external {
        manager = _manager;
    }

    function setFee(uint24 _fee) external {
        fee = _fee;
    }

    function getFee(address, PoolKey calldata) public view returns (uint24) {
        return fee;
    }

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata hookData)
        external
        override
        returns (bytes4)
    {
        // updates the dynamic fee in the pool if update is true
        bool _update;
        uint24 _fee;

        if (hookData.length > 0) {
            (_update, _fee) = abi.decode(hookData, (bool, uint24));
        }
        if (_update == true) {
            fee = _fee;

            manager.setDynamicFee(key);
        }
        return IHooks.beforeSwap.selector;
    }
}
