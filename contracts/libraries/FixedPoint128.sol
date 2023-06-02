// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import {FullMath} from "./FullMath.sol";

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

/// @notice Add two UQ128x128 numbers together, reverts on overflow relying on checked math on uint256
function add(UQ128x128 a, UQ128x128 b) pure returns (UQ128x128) {
    return UQ128x128.wrap(UQ128x128.unwrap(a) + UQ128x128.unwrap(b));
}

/// @notice Subtract one UQ128x128 number from another, reverts on underflow relying on checked math on uint256
function sub(UQ128x128 a, UQ128x128 b) pure returns (UQ128x128) {
    return UQ128x128.wrap(UQ128x128.unwrap(a) - UQ128x128.unwrap(b));
}

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

function mul(UQ128x128 a, UQ128x128 b) pure returns (UQ128x128) {
    return UQ128x128.wrap(FullMath.mulDiv(a.toUint256(), b.toUint256(), 2 ** 128));
}

function div(UQ128x128 a, UQ128x128 b) pure returns (UQ128x128) {
    return UQ128x128.wrap(FullMath.mulDiv(UQ128x128.unwrap(a), 2 ** 128, UQ128x128.unwrap(b)));
}

/// @title FixedPoint128
/// @notice A library for handling binary fixed point numbers, see https://en.wikipedia.org/wiki/Q_(number_format)
library FixedPoint128 {
    uint8 internal constant RESOLUTION = 128;
    uint256 internal constant Q128 = 0x100000000000000000000000000000000;

    function uncheckedAdd(UQ128x128 a, UQ128x128 b) internal pure returns (UQ128x128) {
        unchecked {
            return UQ128x128.wrap(UQ128x128.unwrap(a) + UQ128x128.unwrap(b));
        }
    }

    function uncheckedSub(UQ128x128 a, UQ128x128 b) internal pure returns (UQ128x128) {
        unchecked {
            return UQ128x128.wrap(UQ128x128.unwrap(a) - UQ128x128.unwrap(b));
        }
    }

    function uncheckedMul(UQ128x128 a, UQ128x128 b) internal pure returns (UQ128x128) {
        unchecked {
            if (
                b == UQ128x128.wrap(0)
                    || (UQ128x128.unwrap(a) * UQ128x128.unwrap(b) / UQ128x128.unwrap(b) == UQ128x128.unwrap(a))
            ) {
                return UQ128x128.wrap((UQ128x128.unwrap(a) * UQ128x128.unwrap(b)) / 2 ** 128);
            }
            return UQ128x128.wrap(FullMath.mulDiv(UQ128x128.unwrap(a), UQ128x128.unwrap(b), 2 ** 128));
        }
    }

    function uncheckedDiv(UQ128x128 a, UQ128x128 b) internal pure returns (UQ128x128) {
        unchecked {
            if ((UQ128x128.unwrap(a) * 2 ** 128) / 2 ** 128 == UQ128x128.unwrap(a)) {
                return UQ128x128.wrap((UQ128x128.unwrap(a) * 2 ** 128 / UQ128x128.unwrap(b)));
            }
            return UQ128x128.wrap(FullMath.mulDiv(UQ128x128.unwrap(a), 2 ** 128, UQ128x128.unwrap(b)));
        }
    }

    /// returns uint256 of the same data reprensentation
    function toUint256(UQ128x128 self) internal pure returns (uint256) {
        return UQ128x128.unwrap(self);
    }
}
