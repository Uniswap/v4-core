// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {Hooks} from "../libraries/Hooks.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";

contract MockHooksSimple is IHooks {
    mapping(bytes4 => bytes4) public returnValues;

    function beforeInitialize(address, IPoolManager.PoolKey memory, uint160) external pure override returns (bytes4) {
        bytes4 selector = MockHooksSimple.beforeInitialize.selector;
        return selector;
    }

    function afterInitialize(address, IPoolManager.PoolKey memory, uint160, int24)
        external
        pure
        override
        returns (bytes4)
    {
        bytes4 selector = MockHooksSimple.afterInitialize.selector;
        return selector;
    }

    function beforeModifyPosition(address, IPoolManager.PoolKey calldata, IPoolManager.ModifyPositionParams calldata)
        external
        pure
        override
        returns (bytes4)
    {
        bytes4 selector = MockHooksSimple.beforeModifyPosition.selector;
        return selector;
    }

    function afterModifyPosition(
        address,
        IPoolManager.PoolKey calldata,
        IPoolManager.ModifyPositionParams calldata,
        IPoolManager.BalanceDelta calldata
    ) external pure override returns (bytes4) {
        bytes4 selector = MockHooksSimple.afterModifyPosition.selector;
        return selector;
    }

    function beforeSwap(address, IPoolManager.PoolKey calldata, IPoolManager.SwapParams calldata)
        external
        pure
        override
        returns (bytes4)
    {
        bytes4 selector = MockHooksSimple.beforeSwap.selector;
        return selector;
    }

    function afterSwap(
        address,
        IPoolManager.PoolKey calldata,
        IPoolManager.SwapParams calldata,
        IPoolManager.BalanceDelta calldata
    ) external pure override returns (bytes4) {
        bytes4 selector = MockHooksSimple.afterSwap.selector;
        return selector;
    }

    function beforeDonate(address, IPoolManager.PoolKey calldata, uint256, uint256)
        external
        pure
        override
        returns (bytes4)
    {
        bytes4 selector = MockHooksSimple.beforeDonate.selector;
        return selector;
    }

    function afterDonate(address, IPoolManager.PoolKey calldata, uint256, uint256)
        external
        pure
        override
        returns (bytes4)
    {
        bytes4 selector = MockHooksSimple.afterDonate.selector;
        return selector;
    }

    function setReturnValue(bytes4 key, bytes4 value) external {
        returnValues[key] = value;
    }
}
