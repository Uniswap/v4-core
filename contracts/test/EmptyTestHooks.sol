// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Hooks} from "../libraries/Hooks.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";

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
                afterSwap: true,
                beforeDonate: true,
                afterDonate: true
            })
        );
    }

    function beforeInitialize(address, IPoolManager.PoolKey memory, uint160) external pure override returns (bytes4) {
        return IHooks.beforeInitialize.selector;
    }

    function afterInitialize(address, IPoolManager.PoolKey memory, uint160, int24)
        external
        pure
        override
        returns (bytes4)
    {
        return IHooks.afterInitialize.selector;
    }

    function beforeModifyPosition(address, IPoolManager.PoolKey calldata, IPoolManager.ModifyPositionParams calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IHooks.beforeModifyPosition.selector;
    }

    function afterModifyPosition(
        address,
        IPoolManager.PoolKey calldata,
        IPoolManager.ModifyPositionParams calldata,
        BalanceDelta
    ) external pure override returns (bytes4) {
        return IHooks.afterModifyPosition.selector;
    }

    function beforeSwap(address, IPoolManager.PoolKey calldata, IPoolManager.SwapParams calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IHooks.beforeSwap.selector;
    }

    function afterSwap(address, IPoolManager.PoolKey calldata, IPoolManager.SwapParams calldata, BalanceDelta)
        external
        pure
        override
        returns (bytes4)
    {
        return IHooks.afterSwap.selector;
    }

    function beforeDonate(address, IPoolManager.PoolKey calldata, uint256, uint256)
        external
        pure
        override
        returns (bytes4)
    {
        return IHooks.beforeDonate.selector;
    }

    function afterDonate(address, IPoolManager.PoolKey calldata, uint256, uint256)
        external
        pure
        override
        returns (bytes4)
    {
        return IHooks.afterDonate.selector;
    }
}
