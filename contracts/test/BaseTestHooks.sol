// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IHooks} from "../interfaces/IHooks.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";

contract BaseTestHooks is IHooks {
    error HookNotImplemented();

    function beforeInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96, bytes calldata hookData)
        external
        virtual
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterInitialize(
        address sender,
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        int24 tick,
        bytes calldata hookData
    ) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function beforeModifyPosition(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyPositionParams calldata params,
        bytes calldata hookData
    ) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterModifyPosition(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyPositionParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function beforeDonate(
        address sender,
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1,
        bytes calldata hookData
    ) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterDonate(
        address sender,
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1,
        bytes calldata hookData
    ) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }
}
