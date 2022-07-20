// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {IPoolManager} from '../../interfaces/IPoolManager.sol';
import {IHooks} from '../../interfaces/IHooks.sol';

abstract contract BaseHook is IHooks {
    error NotPoolManager();
    error NotSelf();
    error InvalidPool();
    error LockFailure();
    error HookNotImplemented();

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

    /// @dev Only this address may call this function
    modifier selfOnly() {
        if (msg.sender != address(this)) revert NotSelf();
        _;
    }

    /// @dev Only pools with hooks set to this contract may call this function
    modifier onlyValidPools(IHooks hooks) {
        if (hooks != this) revert InvalidPool();
        _;
    }

    function lockAcquired(bytes calldata data) external virtual poolManagerOnly returns (bytes memory) {
        (bool success, bytes memory returnData) = address(this).call(data);
        if (success) return returnData;
        if (returnData.length == 0) revert LockFailure();
        // if the call failed, bubble up the reason
        /// @solidity memory-safe-assembly
        assembly {
            revert(add(returnData, 32), mload(returnData))
        }
    }

    function beforeInitialize(
        address,
        IPoolManager.PoolKey calldata,
        uint160
    ) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterInitialize(
        address,
        IPoolManager.PoolKey calldata,
        uint160,
        int24
    ) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function beforeModifyPosition(
        address,
        IPoolManager.PoolKey calldata,
        IPoolManager.ModifyPositionParams calldata
    ) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterModifyPosition(
        address,
        IPoolManager.PoolKey calldata,
        IPoolManager.ModifyPositionParams calldata,
        IPoolManager.BalanceDelta calldata
    ) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function beforeSwap(
        address,
        IPoolManager.PoolKey calldata,
        IPoolManager.SwapParams calldata
    ) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterSwap(
        address,
        IPoolManager.PoolKey calldata,
        IPoolManager.SwapParams calldata,
        IPoolManager.BalanceDelta calldata
    ) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function beforeDonate(
        address,
        IPoolManager.PoolKey calldata,
        uint256,
        uint256
    ) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterDonate(
        address,
        IPoolManager.PoolKey calldata,
        uint256,
        uint256
    ) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }
}
