// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Hooks} from "../libraries/Hooks.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {IHookFeeManager} from "../interfaces/IHookFeeManager.sol";
import {PoolId} from "../libraries/PoolId.sol";

contract MockHooks is IHooks, IHookFeeManager {
    using PoolId for IPoolManager.PoolKey;
    using Hooks for IHooks;

    mapping(bytes4 => bytes4) public returnValues;

    mapping(bytes32 => uint8) public swapFees;

    mapping(bytes32 => uint8) public withdrawFees;

    function beforeInitialize(address, IPoolManager.PoolKey memory, uint160) external view override returns (bytes4) {
        bytes4 selector = MockHooks.beforeInitialize.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function afterInitialize(address, IPoolManager.PoolKey memory, uint160, int24)
        external
        view
        override
        returns (bytes4)
    {
        bytes4 selector = MockHooks.afterInitialize.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function beforeModifyPosition(address, IPoolManager.PoolKey calldata, IPoolManager.ModifyPositionParams calldata)
        external
        view
        override
        returns (bytes4)
    {
        bytes4 selector = MockHooks.beforeModifyPosition.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function afterModifyPosition(
        address,
        IPoolManager.PoolKey calldata,
        IPoolManager.ModifyPositionParams calldata,
        BalanceDelta
    ) external view override returns (bytes4) {
        bytes4 selector = MockHooks.afterModifyPosition.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function beforeSwap(address, IPoolManager.PoolKey calldata, IPoolManager.SwapParams calldata)
        external
        view
        override
        returns (bytes4)
    {
        bytes4 selector = MockHooks.beforeSwap.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function afterSwap(address, IPoolManager.PoolKey calldata, IPoolManager.SwapParams calldata, BalanceDelta)
        external
        view
        override
        returns (bytes4)
    {
        bytes4 selector = MockHooks.afterSwap.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function beforeDonate(address, IPoolManager.PoolKey calldata, uint256, uint256)
        external
        view
        override
        returns (bytes4)
    {
        bytes4 selector = MockHooks.beforeDonate.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function afterDonate(address, IPoolManager.PoolKey calldata, uint256, uint256)
        external
        view
        override
        returns (bytes4)
    {
        bytes4 selector = MockHooks.afterDonate.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function getHookSwapFee(IPoolManager.PoolKey calldata key) external view override returns (uint8) {
        return swapFees[key.toId()];
    }

    function getHookWithdrawFee(IPoolManager.PoolKey calldata key) external view override returns (uint8) {
        return withdrawFees[key.toId()];
    }

    function setReturnValue(bytes4 key, bytes4 value) external {
        returnValues[key] = value;
    }

    function setSwapFee(IPoolManager.PoolKey calldata key, uint8 value) external {
        swapFees[key.toId()] = value;
    }

    function setWithdrawFee(IPoolManager.PoolKey calldata key, uint8 value) external {
        withdrawFees[key.toId()] = value;
    }
}
