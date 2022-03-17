// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IHooks} from '../interfaces/callback/IHooks.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';
import {Pool} from '../libraries/Pool.sol';

contract EmptyTestHooks is IHooks {
    mapping(string => bool) called;

    function beforeModifyPosition(
        address sender,
        IPoolManager.PoolKey calldata key,
        IPoolManager.ModifyPositionParams calldata params
    ) external override {}

    function afterModifyPosition(
        address sender,
        IPoolManager.PoolKey calldata key,
        IPoolManager.ModifyPositionParams calldata params
    ) external override {}

    function beforeSwap(
        address sender,
        IPoolManager.PoolKey calldata key,
        IPoolManager.SwapParams calldata params
    ) external override {}

    function afterSwap(
        address sender,
        IPoolManager.PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        Pool.BalanceDelta calldata delta
    ) external override {}
}

contract TestHooks is IHooks {
    mapping(string => bool) public called;

    function beforeModifyPosition(
        address,
        IPoolManager.PoolKey calldata,
        IPoolManager.ModifyPositionParams calldata
    ) external override {
        called['beforeModifyPosition'] = true;
    }

    function afterModifyPosition(
        address,
        IPoolManager.PoolKey calldata,
        IPoolManager.ModifyPositionParams calldata
    ) external override {
        called['afterModifyPosition'] = true;
    }

    function beforeSwap(
        address,
        IPoolManager.PoolKey calldata,
        IPoolManager.SwapParams calldata
    ) external override {
        called['beforeSwap'] = true;
    }

    function afterSwap(
        address,
        IPoolManager.PoolKey calldata,
        IPoolManager.SwapParams calldata,
        Pool.BalanceDelta calldata
    ) external override {
        called['afterSwap'] = true;
    }
}
