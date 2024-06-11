// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeCast} from "../libraries/SafeCast.sol";

/// @dev Two `int128` values packed into a single `int256` where the upper 128 bits represent the amount0
/// and the lower 128 bits represent the amount1.
type BalanceDeltas is int256;

using {add as +, sub as -, eq as ==, neq as !=} for BalanceDeltas global;
using BalanceDeltasLibrary for BalanceDeltas global;
using SafeCast for int256;

function toBalanceDeltas(int128 _amount0, int128 _amount1) pure returns (BalanceDeltas balanceDeltas) {
    assembly {
        balanceDeltas := or(shl(128, _amount0), and(sub(shl(128, 1), 1), _amount1))
    }
}

function add(BalanceDeltas a, BalanceDeltas b) pure returns (BalanceDeltas) {
    int256 res0;
    int256 res1;
    assembly {
        let a0 := sar(128, a)
        let a1 := signextend(15, a)
        let b0 := sar(128, b)
        let b1 := signextend(15, b)
        res0 := add(a0, b0)
        res1 := add(a1, b1)
    }
    return toBalanceDeltas(res0.toInt128(), res1.toInt128());
}

function sub(BalanceDeltas a, BalanceDeltas b) pure returns (BalanceDeltas) {
    int256 res0;
    int256 res1;
    assembly {
        let a0 := sar(128, a)
        let a1 := signextend(15, a)
        let b0 := sar(128, b)
        let b1 := signextend(15, b)
        res0 := sub(a0, b0)
        res1 := sub(a1, b1)
    }
    return toBalanceDeltas(res0.toInt128(), res1.toInt128());
}

function eq(BalanceDeltas a, BalanceDeltas b) pure returns (bool) {
    return BalanceDeltas.unwrap(a) == BalanceDeltas.unwrap(b);
}

function neq(BalanceDeltas a, BalanceDeltas b) pure returns (bool) {
    return BalanceDeltas.unwrap(a) != BalanceDeltas.unwrap(b);
}

library BalanceDeltasLibrary {
    BalanceDeltas public constant ZERO_DELTAS = BalanceDeltas.wrap(0);

    function amount0(BalanceDeltas balanceDeltas) internal pure returns (int128 _amount0) {
        assembly {
            _amount0 := sar(128, balanceDeltas)
        }
    }

    function amount1(BalanceDeltas balanceDeltas) internal pure returns (int128 _amount1) {
        assembly {
            _amount1 := signextend(15, balanceDeltas)
        }
    }
}
