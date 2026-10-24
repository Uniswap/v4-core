// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title FixedPoint128
/// @notice A library for handling binary fixed point numbers in Q128 format
/// @dev This library provides the Q128 constant used for fixed-point arithmetic with 128 fractional bits.
/// The Q128 format represents numbers as: value = rawValue / 2^128
/// This is primarily used in Uniswap v4 for tracking fee growth per unit of liquidity,
/// where high precision is required to accurately accumulate fees over many transactions.
/// See https://en.wikipedia.org/wiki/Q_(number_format) for more information on Q number formats.
library FixedPoint128 {
    /// @notice The Q128 constant representing 2^128
    /// @dev Used as the denominator in Q128 fixed-point calculations.
    /// Q128 = 2^128 = 340282366920938463463374607431768211456
    /// In hex: 0x100000000000000000000000000000000 (1 followed by 32 zeros)
    /// @dev Example usage: To convert a Q128 value to a regular number, divide by Q128
    /// realValue = q128Value / Q128
    uint256 internal constant Q128 = 0x100000000000000000000000000000000;
}
