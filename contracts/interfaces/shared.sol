// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

/// @notice Represents a change in the pool's balance of token0 and token1.
struct BalanceDelta {
    int256 amount0;
    int256 amount1;
}
