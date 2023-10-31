// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Hooks} from "../libraries/Hooks.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {IHookFeeManager} from "../interfaces/IHookFeeManager.sol";
import {PoolId, PoolIdLibrary} from "../types/PoolId.sol";

contract MockHooks is IHooks, IHookFeeManager {
    using PoolIdLibrary for PoolKey;
    using Hooks for IHooks;

    bytes public beforeInitializeData;
    bytes public afterInitializeData;
    bytes public beforeModifyPositionData;
    bytes public afterModifyPositionData;
    bytes public beforeSwapData;
    bytes public afterSwapData;
    bytes public beforeDonateData;
    bytes public afterDonateData;

    mapping(bytes4 => bytes4) public returnValues;

    mapping(PoolId => uint16) public swapFees;

    mapping(PoolId => uint16) public withdrawFees;

    function beforeInitialize(address, PoolKey calldata, uint160, bytes calldata hookData)
        external
        override
        returns (bytes4)
    {
        beforeInitializeData = hookData;
        bytes4 selector = MockHooks.beforeInitialize.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24, bytes calldata hookData)
        external
        override
        returns (bytes4)
    {
        afterInitializeData = hookData;
        bytes4 selector = MockHooks.afterInitialize.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function beforeModifyPosition(
        address,
        PoolKey calldata,
        IPoolManager.ModifyPositionParams calldata,
        bytes calldata hookData
    ) external override returns (bytes4) {
        beforeModifyPositionData = hookData;
        bytes4 selector = MockHooks.beforeModifyPosition.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function afterModifyPosition(
        address,
        PoolKey calldata,
        IPoolManager.ModifyPositionParams calldata,
        BalanceDelta,
        bytes calldata hookData
    ) external override returns (bytes4) {
        afterModifyPositionData = hookData;
        bytes4 selector = MockHooks.afterModifyPosition.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function beforeSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, bytes calldata hookData)
        external
        override
        returns (bytes4)
    {
        beforeSwapData = hookData;
        bytes4 selector = MockHooks.beforeSwap.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function afterSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata hookData
    ) external override returns (bytes4) {
        afterSwapData = hookData;
        bytes4 selector = MockHooks.afterSwap.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata hookData)
        external
        override
        returns (bytes4)
    {
        beforeDonateData = hookData;
        bytes4 selector = MockHooks.beforeDonate.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata hookData)
        external
        override
        returns (bytes4)
    {
        afterDonateData = hookData;
        bytes4 selector = MockHooks.afterDonate.selector;
        return returnValues[selector] == bytes4(0) ? selector : returnValues[selector];
    }

    function getHookFees(PoolKey calldata key) external view override returns (uint24) {
        return (uint24(swapFees[key.toId()]) << 12 | withdrawFees[key.toId()]);
    }

    function setReturnValue(bytes4 key, bytes4 value) external {
        returnValues[key] = value;
    }

    function setSwapFee(PoolKey calldata key, uint16 value) external {
        swapFees[key.toId()] = value;
    }

    function setWithdrawFee(PoolKey calldata key, uint16 value) external {
        withdrawFees[key.toId()] = value;
    }
}
