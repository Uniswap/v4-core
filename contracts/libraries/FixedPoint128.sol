// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

type UQ128x128 is uint256;

using {
    add as +,
    sub as -,
    eq as ==,
    neq as !=,
    lt as <,
    gt as >,
    lte as <=,
    gte as >=,
    div as /,
    mul as *
} for UQ128x128 global;

using FixedPoint128 for UQ128x128 global;

// Add two UQ128x128 numbers together, reverts on overflow relying on checked math on uint256
function add(UQ128x128 a, UQ128x128 b) pure returns (UQ128x128) {
    return UQ128x128.wrap(UQ128x128.unwrap(a) + UQ128x128.unwrap(b));
}

// Subtract one UQ128x128 number from another, reverts on underflow relying on checked math on uint256
function sub(UQ128x128 a, UQ128x128 b) pure returns (UQ128x128) {
    return UQ128x128.wrap(UQ128x128.unwrap(a) - UQ128x128.unwrap(b));
}

/// Comparison operators
function eq(UQ128x128 a, UQ128x128 b) pure returns (bool) {
    return UQ128x128.unwrap(a) == UQ128x128.unwrap(b);
}

function neq(UQ128x128 a, UQ128x128 b) pure returns (bool) {
    return UQ128x128.unwrap(a) != UQ128x128.unwrap(b);
}

function lt(UQ128x128 a, UQ128x128 b) pure returns (bool) {
    return UQ128x128.unwrap(a) < UQ128x128.unwrap(b);
}

function gt(UQ128x128 a, UQ128x128 b) pure returns (bool) {
    return UQ128x128.unwrap(a) > UQ128x128.unwrap(b);
}

function lte(UQ128x128 a, UQ128x128 b) pure returns (bool) {
    return UQ128x128.unwrap(a) <= UQ128x128.unwrap(b);
}

function gte(UQ128x128 a, UQ128x128 b) pure returns (bool) {
    return UQ128x128.unwrap(a) >= UQ128x128.unwrap(b);
}

// TODO: mul, div
function mul(UQ128x128 a, UQ128x128 b) pure returns (UQ128x128) {}

function div(UQ128x128 a, UQ128x128 b) pure returns (UQ128x128) {
    // TODO: is this right? seems to be easier than 64x96 since 128x128 fills entire uint256
    return UQ128x128.wrap((UQ128x128.unwrap(a) * 2 ** 96) / UQ128x128.unwrap(b));
}

/// @title FixedPoint128
/// @notice A library for handling binary fixed point numbers, see https://en.wikipedia.org/wiki/Q_(number_format)
library FixedPoint128 {
    uint256 internal constant Q128 = 0x100000000000000000000000000000000;

    function toUint256(UQ128x128 self) internal pure returns (uint256) {
        return UQ128x128.unwrap(self);
    }
}


