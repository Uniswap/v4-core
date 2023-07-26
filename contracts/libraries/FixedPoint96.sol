// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {FullMath} from "./FullMath.sol";
import {SafeCast} from "./SafeCast.sol";

type UQ64x96 is uint160;

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
} for UQ64x96 global;

using FixedPoint96 for UQ64x96 global;
using SafeCast for uint256;

function add(UQ64x96 a, UQ64x96 b) pure returns (UQ64x96) {
    return UQ64x96.wrap(UQ64x96.unwrap(a) + UQ64x96.unwrap(b));
}

function sub(UQ64x96 a, UQ64x96 b) pure returns (UQ64x96) {
    return UQ64x96.wrap(UQ64x96.unwrap(a) - UQ64x96.unwrap(b));
}

function eq(UQ64x96 a, UQ64x96 b) pure returns (bool) {
    return UQ64x96.unwrap(a) == UQ64x96.unwrap(b);
}

function neq(UQ64x96 a, UQ64x96 b) pure returns (bool) {
    return UQ64x96.unwrap(a) != UQ64x96.unwrap(b);
}

function lt(UQ64x96 a, UQ64x96 b) pure returns (bool) {
    return UQ64x96.unwrap(a) < UQ64x96.unwrap(b);
}

function gt(UQ64x96 a, UQ64x96 b) pure returns (bool) {
    return UQ64x96.unwrap(a) > UQ64x96.unwrap(b);
}

function lte(UQ64x96 a, UQ64x96 b) pure returns (bool) {
    return UQ64x96.unwrap(a) <= UQ64x96.unwrap(b);
}

function gte(UQ64x96 a, UQ64x96 b) pure returns (bool) {
    return UQ64x96.unwrap(a) >= UQ64x96.unwrap(b);
}

function div(UQ64x96 a, UQ64x96 b) pure returns (UQ64x96) {
    return UQ64x96.wrap((a.toUint256() * 2 ** 96 / b.toUint256()).toUint160());
}

function mul(UQ64x96 a, UQ64x96 b) pure returns (UQ64x96) {
    return UQ64x96.wrap(FullMath.mulDiv(a.toUint256(), b.toUint256(), 2 ** 96).toUint160());
}

/// @title FixedPoint96
/// @notice A library for handling binary fixed point numbers, see https://en.wikipedia.org/wiki/Q_(number_format)
/// @dev Used in SqrtPriceMath.sol
library FixedPoint96 {
    uint8 internal constant RESOLUTION = 96;
    uint256 internal constant ONE = 0x1000000000000000000000000;

    function toUint256(UQ64x96 self) internal pure returns (uint256) {
        return UQ64x96.unwrap(self);
    }

    function uncheckedAdd(UQ64x96 a, UQ64x96 b) internal pure returns (UQ64x96) {
        unchecked {
            return UQ64x96.wrap(UQ64x96.unwrap(a) + UQ64x96.unwrap(b));
        }
    }

    function uncheckedSub(UQ64x96 a, UQ64x96 b) internal pure returns (UQ64x96) {
        unchecked {
            return UQ64x96.wrap(UQ64x96.unwrap(a) - UQ64x96.unwrap(b));
        }
    }

    function uncheckedMul(UQ64x96 a, UQ64x96 b) internal pure returns (UQ64x96) {
        unchecked {
            if (b != UQ64x96.wrap(0) && a.toUint256() * b.toUint256() / b.toUint256() != a.toUint256()) {
                return UQ64x96.wrap(FullMath.mulDiv(a.toUint256(), b.toUint256(), 2 ** 96).toUint160());
            }
            return UQ64x96.wrap((a.toUint256() * b.toUint256() / 2 ** 96).toUint160());
        }
    }

    function uncheckedDiv(UQ64x96 a, UQ64x96 b) internal pure returns (UQ64x96) {
        unchecked {
            return UQ64x96.wrap((a.toUint256() * 2 ** 96 / b.toUint256()).toUint160());
        }
    }
}
