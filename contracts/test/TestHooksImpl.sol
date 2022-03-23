// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {Hooks} from '../libraries/Hooks.sol';
import {IHooks} from '../interfaces/IHooks.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';

contract EmptyTestHooks is IHooks {
    using Hooks for IHooks;

    constructor() {
        IHooks(this).validateHookAddress(
            Hooks.Calls({
                beforeInitialize: true,
                afterInitialize: true,
                beforeModifyPosition: true,
                afterModifyPosition: true,
                beforeSwap: true,
                afterSwap: true
            })
        );
    }

    function beforeInitialize(
        address sender,
        IPoolManager.PoolKey memory key,
        uint160 sqrtPriceX96
    ) external override {}

    function afterInitialize(
        address sender,
        IPoolManager.PoolKey memory key,
        uint160 sqrtPriceX96,
        int24 tick
    ) external override {}

    function beforeModifyPosition(
        address sender,
        IPoolManager.PoolKey calldata key,
        IPoolManager.ModifyPositionParams calldata params
    ) external override {}

    function afterModifyPosition(
        address sender,
        IPoolManager.PoolKey calldata key,
        IPoolManager.ModifyPositionParams calldata params,
        IPoolManager.BalanceDelta calldata delta
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
        IPoolManager.BalanceDelta calldata delta
    ) external override {}
}
