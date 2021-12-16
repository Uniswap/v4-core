// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.2;

import {IPoolImplementation} from '../IPoolImplementation.sol';
import {IERC20Minimal} from '../external/IERC20Minimal.sol';
import {Pool} from '../../libraries/Pool.sol';

interface IV3PoolImplementation is IPoolImplementation {
    /// @notice The data that is encoded in the IPoolImplementation#modifyPosition data argument
    struct ModifyPositionParams {
        address owner;
        int24 tickLower;
        int24 tickUpper;
        int256 liquidityDelta;
    }

    /// @notice The data that is encoded in the IPoolImplementation#swap data argument
    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Returns the fee in pips taken on input to all swaps
    function fee() external view returns (uint24);

    /// @notice Returns the number by which all initialized ticks must be evenly divisible
    function tickSpacing() external view returns (int24);

    /// @notice Returns the max liquidity that may be contained on any individual tick
    function maxLiquidityPerTick() external view returns (uint128);

    /// @notice Initialize the state for a given pool ID
    function initialize(
        IERC20Minimal token0,
        IERC20Minimal token1,
        uint160 sqrtPriceX96
    ) external returns (int24 tick);

    /// @notice Increase the maximum number of stored observations for the pool's oracle
    function increaseObservationCardinalityNext(
        IERC20Minimal token0,
        IERC20Minimal token1,
        uint16 observationCardinalityNext
    ) external returns (uint16 observationCardinalityNextOld, uint16 observationCardinalityNextNew);

    /// @notice Update the protocol fee for a given pool
    function setFeeProtocol(
        IERC20Minimal token0,
        IERC20Minimal token1,
        uint8 feeProtocol
    ) external returns (uint8 feeProtocolOld);

    /// @notice Observe a past state of a pool
    function observe(
        IERC20Minimal token0,
        IERC20Minimal token1,
        uint32[] calldata secondsAgos
    ) external view returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);

    /// @notice Get the snapshot of the cumulative values of a tick range
    function snapshotCumulativesInside(
        IERC20Minimal token0,
        IERC20Minimal token1,
        int24 tickLower,
        int24 tickUpper
    ) external view returns (Pool.Snapshot memory);
}
