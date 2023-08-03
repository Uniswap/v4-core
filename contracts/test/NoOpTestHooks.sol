// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Hooks} from "../libraries/Hooks.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";

contract NoOpTestHooks is IHooks {
    using Hooks for IHooks;

    constructor() {
        IHooks(this).validateHookAddress(
            Hooks.Calls({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: true,
                afterModifyPosition: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: true,
                afterDonate: false,
                noOp: true
            })
        );
    }

    function beforeInitialize(address, PoolKey memory, uint160) external pure override returns (bytes4) {
        return bytes4(0);
    }

    function afterInitialize(address, PoolKey memory, uint160, int24) external pure override returns (bytes4) {
        return bytes4(0);
    }

    function beforeModifyPosition(address, PoolKey calldata, IPoolManager.ModifyPositionParams calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return Hooks.NO_OP_SELECTOR;
    }

    function afterModifyPosition(address, PoolKey calldata, IPoolManager.ModifyPositionParams calldata, BalanceDelta)
        external
        pure
        override
        returns (bytes4)
    {
        return bytes4(0);
    }

    function beforeSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return Hooks.NO_OP_SELECTOR;
    }

    function afterSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, BalanceDelta)
        external
        pure
        override
        returns (bytes4)
    {
        return bytes4(0);
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256)
        external
        pure
        override
        returns (bytes4)
    {
        return Hooks.NO_OP_SELECTOR;
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256) external pure override returns (bytes4) {
        return bytes4(0);
    }
}
