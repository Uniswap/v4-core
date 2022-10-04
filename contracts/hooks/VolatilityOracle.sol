// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import {IPoolManager} from '../interfaces/IPoolManager.sol';
import {IHooks} from '../interfaces/IHooks.sol';
import {IDynamicFeeManager} from '../interfaces/IDynamicFeeManager.sol';
import {BaseHook} from './base/BaseHook.sol';
import {Hooks} from '../libraries/Hooks.sol';


contract VolatilityOracle is BaseHook, IDynamicFeeManager {
    uint32 deployTimestamp;

    function getFee(
        IPoolManager.PoolKey calldata
    ) external view returns (uint24) {
        uint24 fee = 3000;
        uint32 lapsed = deployTimestamp - _blockTimestamp();
        return fee + uint24(lapsed) * 100 / 60; // 100 bps a minute
    }

    /// @dev For mocking
    function _blockTimestamp() internal view virtual returns (uint32) {
        return uint32(block.timestamp);
    }

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        Hooks.validateHookAddress(
            this,
            Hooks.Calls({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: false,
                afterModifyPosition: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
            })
        );
        deployTimestamp = _blockTimestamp();
    }

    
}
