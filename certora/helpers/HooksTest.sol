
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Hooks} from "src/libraries/Hooks.sol";
import {IHooks} from "src/interfaces/IHooks.sol";
import {PoolKey} from "src/types/PoolKey.sol";
import {IPoolManager} from "src/interfaces/IPoolManager.sol";
import {BeforeSwapDelta} from "src/types/BeforeSwapDelta.sol";

contract HooksTest {

    using Hooks for IHooks;

    function beforeSwap(
        address self, 
        PoolKey memory key, 
        IPoolManager.SwapParams memory params, 
        bytes calldata hookData
    ) external returns (int256 amountToSwap, BeforeSwapDelta hookReturn, uint24 lpFeeOverride) 
    {
        return IHooks(self).beforeSwap(key, params, hookData);
    }
}