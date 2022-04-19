// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {IHooks} from '../interfaces/IHooks.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';
import {Hooks} from '../libraries/Hooks.sol';

/// @notice Includes the Oracle feature in a similar way to V3. This is now externalized
contract V3Oracle is IHooks {
    constructor() {
        Hooks.validateHookAddress(
            this,
            Hooks.Calls({
                beforeInitialize: false,
                // to initialize the observations for the pool
                afterInitialize: true,
                // to record the tick at the start of the block for the pool
                beforeModifyPosition: true,
                afterModifyPosition: false,
                // to record the tick at the start of the block for the pool
                beforeSwap: true,
                afterSwap: false
            })
        );
    }

    function beforeInitialize(
        address sender,
        IPoolManager.PoolKey memory key,
        uint160 sqrtPriceX96
    ) external override {
        revert();
    }

    function afterInitialize(
        address sender,
        IPoolManager.PoolKey memory key,
        uint160 sqrtPriceX96,
        int24 tick
    ) external override {
        revert();
    }

    function beforeModifyPosition(
        address sender,
        IPoolManager.PoolKey calldata key,
        IPoolManager.ModifyPositionParams calldata params
    ) external override {
        revert();
    }

    function afterModifyPosition(
        address sender,
        IPoolManager.PoolKey calldata key,
        IPoolManager.ModifyPositionParams calldata params,
        IPoolManager.BalanceDelta calldata delta
    ) external override {
        revert();
    }

    function beforeSwap(
        address sender,
        IPoolManager.PoolKey calldata key,
        IPoolManager.SwapParams calldata params
    ) external override {
        revert();
    }

    function afterSwap(
        address sender,
        IPoolManager.PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        IPoolManager.BalanceDelta calldata delta
    ) external override {
        revert();
    }


//    /// @notice Observe a past state of a pool
//    function observe(PoolKey calldata key, uint32[] calldata secondsAgos)
//    external
//    view
//    returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);
//
//    /// @notice Get the snapshot of the cumulative values of a tick range
//    function snapshotCumulativesInside(
//        PoolKey calldata key,
//        int24 tickLower,
//        int24 tickUpper
//    ) external view returns (Pool.Snapshot memory);

    /// @dev Increase the number of stored observations
//    function observe(
//        IPoolManager.PoolKey calldata key,
//        uint32[] calldata secondsAgos
//    ) external view returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) {
//        return observations[key].observe(
//            time,
//            secondsAgos,
//            self.slot0.tick,
//            self.slot0.observationIndex,
//            self.liquidity,
//            self.slot0.observationCardinality
//        );
//    }
//
//    /// @dev Increase the number of stored observations
//    function increaseObservationCardinalityNext(State storage self, uint16 observationCardinalityNext)
//    internal
//    returns (uint16 observationCardinalityNextOld, uint16 observationCardinalityNextNew)
//    {
//        observationCardinalityNextOld = self.slot0.observationCardinalityNext;
//        observationCardinalityNextNew = self.observations.grow(
//            observationCardinalityNextOld,
//            observationCardinalityNext
//        );
//        self.slot0.observationCardinalityNext = observationCardinalityNextNew;
//    }

}
