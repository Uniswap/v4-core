// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title FixedPoint96
/// @notice A library for handling binary fixed point numbers in Q96 format
/// @dev This library provides constants for fixed-point arithmetic with 96 fractional bits.
/// The Q96 format represents numbers as: value = rawValue / 2^96
/// This format is central to Uniswap v4's price representation, where prices are stored as
/// sqrtPriceX96 = sqrt(price) * 2^96. This allows for efficient price calculations while
/// maintaining high precision across a wide range of token price ratios.
/// See https://en.wikipedia.org/wiki/Q_(number_format) for more information on Q number formats.
library FixedPoint96 {
    /// @notice The number of fractional bits in a Q96 fixed-point number
    /// @dev 96 bits of resolution provides approximately 29 decimal digits of precision
    uint8 internal constant RESOLUTION = 96;

    /// @notice The Q96 constant representing 2^96
    /// @dev Used as the denominator in Q96 fixed-point calculations.
    /// Q96 = 2^96 = 79228162514264337593543950336
    /// In hex: 0x1000000000000000000000000 (1 followed by 24 zeros)
    /// @dev Example: sqrtPriceX96 uses this format, so to get the actual sqrt price:
    /// sqrtPrice = sqrtPriceX96 / Q96
    uint256 internal constant Q96 = 0x1000000000000000000000000;
}
