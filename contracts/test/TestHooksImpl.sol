// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {Hooks} from '../libraries/Hooks.sol';
import {IHooks} from '../interfaces/IHooks.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';
import {MockContract} from './MockContract.sol';

contract EmptyTestHooks is MockContract, IHooks {
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

    function beforeInitialize(
        address,
        IPoolManager.PoolKey memory,
        uint160
    ) external pure override returns (bytes4) {
        return IHooks.beforeInitialize.selector;
    }

    function afterInitialize(
        address,
        IPoolManager.PoolKey memory,
        uint160,
        int24
    ) external pure override returns (bytes4) {
        return IHooks.afterInitialize.selector;
    }

    function beforeModifyPosition(
        address,
        IPoolManager.PoolKey calldata,
        IPoolManager.ModifyPositionParams calldata
    ) external pure override returns (bytes4) {
        return IHooks.beforeModifyPosition.selector;
    }

    function afterModifyPosition(
        address,
        IPoolManager.PoolKey calldata,
        IPoolManager.ModifyPositionParams calldata,
        IPoolManager.BalanceDelta calldata
    ) external pure override returns (bytes4) {
        return IHooks.afterModifyPosition.selector;
    }

    function beforeSwap(
        address,
        IPoolManager.PoolKey calldata,
        IPoolManager.SwapParams calldata
    ) external pure override returns (bytes4) {
        return IHooks.beforeSwap.selector;
    }

    function afterSwap(
        address,
        IPoolManager.PoolKey calldata,
        IPoolManager.SwapParams calldata,
        IPoolManager.BalanceDelta calldata
    ) external pure override returns (bytes4) {
        return IHooks.afterSwap.selector;
    }

    function beforeDonate(
        address,
        IPoolManager.PoolKey calldata,
        uint256,
        uint256
    ) external pure override returns (bytes4) {
        return IHooks.beforeDonate.selector;
    }

    function afterDonate(
        address,
        IPoolManager.PoolKey calldata,
        uint256,
        uint256
    ) external pure override returns (bytes4) {
        return IHooks.afterDonate.selector;
    }
}

contract MockHooks is MockContract, IHooks {
    using Hooks for IHooks;
    mapping(bytes4 => bytes4) public returnValues;

    function beforeInitialize(
        address,
        IPoolManager.PoolKey memory,
        uint160
    ) external view override returns (bytes4) {
        bytes4 selector = EmptyTestHooks.beforeInitialize.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function afterInitialize(
        address,
        IPoolManager.PoolKey memory,
        uint160,
        int24
    ) external view override returns (bytes4) {
        bytes4 selector = EmptyTestHooks.afterInitialize.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function beforeModifyPosition(
        address,
        IPoolManager.PoolKey calldata,
        IPoolManager.ModifyPositionParams calldata
    ) external view override returns (bytes4) {
        bytes4 selector = EmptyTestHooks.beforeModifyPosition.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function afterModifyPosition(
        address,
        IPoolManager.PoolKey calldata,
        IPoolManager.ModifyPositionParams calldata,
        IPoolManager.BalanceDelta calldata
    ) external view override returns (bytes4) {
        bytes4 selector = EmptyTestHooks.afterModifyPosition.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function beforeSwap(
        address,
        IPoolManager.PoolKey calldata,
        IPoolManager.SwapParams calldata
    ) external view override returns (bytes4) {
        bytes4 selector = EmptyTestHooks.beforeSwap.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function afterSwap(
        address,
        IPoolManager.PoolKey calldata,
        IPoolManager.SwapParams calldata,
        IPoolManager.BalanceDelta calldata
    ) external view override returns (bytes4) {
        bytes4 selector = EmptyTestHooks.afterSwap.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function beforeDonate(
        address,
        IPoolManager.PoolKey calldata,
        uint256,
        uint256
    ) external view override returns (bytes4) {
        bytes4 selector = EmptyTestHooks.beforeDonate.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function afterDonate(
        address,
        IPoolManager.PoolKey calldata,
        uint256,
        uint256
    ) external view override returns (bytes4) {
        bytes4 selector = EmptyTestHooks.afterDonate.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function setReturnValue(bytes4 key, bytes4 value) external {
        returnValues[key] = value;
    }
}
