// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @notice Represents a particular configuration of a Pool
interface IConfiguration {
    /// @notice Returns the fee in pips for the pool
    function fee() external view returns (uint24);

    /// @notice Returns the spacing of ticks
    function tickSpacing() external view returns (int24);

    /// @notice Returns the maximum amount of liquidity that can be placed on any tick
    function maxLiquidityPerTick() external view returns (uint128);
}
