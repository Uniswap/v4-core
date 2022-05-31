// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {IPoolManager} from '../../interfaces/IPoolManager.sol';
import {IHooks} from '../../interfaces/IHooks.sol';

abstract contract BaseHook is IHooks {
    error NotPoolManager();
    error HookNotImplemented();
    error PoolNotInitialized();

    /// @notice The address of the pool manager
    IPoolManager public immutable poolManager;

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    /// @dev Only the pool manager may call this function
    modifier poolManagerOnly() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    function beforeInitialize(
        address,
        IPoolManager.PoolKey calldata,
        uint160
    ) external virtual override {
        revert HookNotImplemented();
    }

    function afterInitialize(
        address,
        IPoolManager.PoolKey calldata,
        uint160,
        int24
    ) external virtual override {
        revert HookNotImplemented();
    }

    function beforeModifyPosition(
        address,
        IPoolManager.PoolKey calldata,
        IPoolManager.ModifyPositionParams calldata
    ) external virtual override {
        revert HookNotImplemented();
    }

    function afterModifyPosition(
        address,
        IPoolManager.PoolKey calldata,
        IPoolManager.ModifyPositionParams calldata,
        IPoolManager.BalanceDelta calldata
    ) external virtual override {
        revert HookNotImplemented();
    }

    function beforeSwap(
        address,
        IPoolManager.PoolKey calldata,
        IPoolManager.SwapParams calldata
    ) external virtual override {
        revert HookNotImplemented();
    }

    function afterSwap(
        address,
        IPoolManager.PoolKey calldata,
        IPoolManager.SwapParams calldata,
        IPoolManager.BalanceDelta calldata
    ) external virtual override {
        revert HookNotImplemented();
    }

    function beforeDonate(
        address,
        IPoolManager.PoolKey calldata,
        uint256,
        uint256
    ) external virtual override {
        revert HookNotImplemented();
    }

    function afterDonate(
        address,
        IPoolManager.PoolKey calldata,
        uint256,
        uint256
    ) external virtual override {
        revert HookNotImplemented();
    }
}
