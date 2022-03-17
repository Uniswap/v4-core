// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IHooks} from '../interfaces/callback/IHooks.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';
import {Pool} from '../libraries/Pool.sol';

contract EmptyTestHooks is IHooks {
    mapping(string => bool) called;

    function beforeModifyPosition(
        address sender,
        IPoolManager.PoolKey memory key,
        IPoolManager.ModifyPositionParams memory params
    ) external override {}

    function afterModifyPosition(
        address sender,
        IPoolManager.PoolKey memory key,
        IPoolManager.ModifyPositionParams memory params
    ) external override {}

    function beforeSwap(
        address sender,
        IPoolManager.PoolKey memory key,
        IPoolManager.SwapParams memory params
    ) external override {}

    function afterSwap(
        address sender,
        IPoolManager.PoolKey memory key,
        IPoolManager.SwapParams memory params,
        Pool.BalanceDelta memory delta
    ) external override {}
}

contract TestHooks is IHooks {
    mapping(string => bool) public called;

    function beforeModifyPosition(
        address,
        IPoolManager.PoolKey memory,
        IPoolManager.ModifyPositionParams memory
    ) external override {
        called['beforeModifyPosition'] = true;
    }

    function afterModifyPosition(
        address,
        IPoolManager.PoolKey memory,
        IPoolManager.ModifyPositionParams memory
    ) external override {
        called['afterModifyPosition'] = true;
    }

    function beforeSwap(
        address,
        IPoolManager.PoolKey memory,
        IPoolManager.SwapParams memory
    ) external override {
        called['beforeSwap'] = true;
    }

    function afterSwap(
        address,
        IPoolManager.PoolKey memory,
        IPoolManager.SwapParams memory,
        Pool.BalanceDelta memory
    ) external override {
        called['afterSwap'] = true;
    }
}
