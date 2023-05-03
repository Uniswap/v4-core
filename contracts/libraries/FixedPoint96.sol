// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

type Q96 is uint160;

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
} for Q96 global;

function add(Q96 a, Q96 b) pure returns (Q96) {
    return Q96.wrap(Q96.unwrap(a) + Q96.unwrap(b));
}

function sub(Q96 a, Q96 b) pure returns (Q96) {
    return Q96.wrap(Q96.unwrap(a) - Q96.unwrap(b));
}

function eq(Q96 a, Q96 b) pure returns (bool) {
    return Q96.unwrap(a) == Q96.unwrap(b);
}

function neq(Q96 a, Q96 b) pure returns (bool) {
    return Q96.unwrap(a) != Q96.unwrap(b);
}

function lt(Q96 a, Q96 b) pure returns (bool) {
    return Q96.unwrap(a) < Q96.unwrap(b);
}

function gt(Q96 a, Q96 b) pure returns (bool) {
    return Q96.unwrap(a) > Q96.unwrap(b);
}

function lte(Q96 a, Q96 b) pure returns (bool) {
    return Q96.unwrap(a) <= Q96.unwrap(b);
}

function gte(Q96 a, Q96 b) pure returns (bool) {
    return Q96.unwrap(a) >= Q96.unwrap(b);
}

function div(Q96 a, Q96 b) pure returns (Q96) {
    return Q96.wrap((Q96.unwrap(a) * 2 ** 96) / Q96.unwrap(b));
}

function mul(Q96 a, Q96 b) pure returns (Q96) {
    return Q96.wrap((Q96.unwrap(a) * Q96.unwrap(b)) / 2 ** 96);
}

/// @title FixedPoint96
/// @notice A library for handling binary fixed point numbers, see https://en.wikipedia.org/wiki/Q_(number_format)
/// @dev Used in SqrtPriceMath.sol
library FixedPoint96 {
    uint8 internal constant RESOLUTION = 96;
    uint256 internal constant ONE = 0x1000000000000000000000000;

    function toUint256(Q96 self) internal pure returns (uint256) {
        return uint256(Q96.unwrap(self));
    }
}
