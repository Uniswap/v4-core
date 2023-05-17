// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

type BalanceDelta is int256;

using {add as +, sub as -} for BalanceDelta global;
using BalanceDeltaLibrary for BalanceDelta global;

function toBalanceDelta(int128 _amount0, int128 _amount1) pure returns (BalanceDelta) {
    unchecked {
        return BalanceDelta.wrap((int256(_amount0) << 128) | int256(_amount1));
    }
}

function add(BalanceDelta a, BalanceDelta b) pure returns (BalanceDelta) {
    return toBalanceDelta(a.amount0() + b.amount0(), a.amount1() + b.amount1());
}

function sub(BalanceDelta a, BalanceDelta b) pure returns (BalanceDelta) {
    return toBalanceDelta(a.amount0() - b.amount0(), a.amount1() - b.amount1());
}

library BalanceDeltaLibrary {
    function amount0(BalanceDelta balanceDelta) internal pure returns (int128) {
        return int128(BalanceDelta.unwrap(balanceDelta) >> 128);
    }

    function amount1(BalanceDelta balanceDelta) internal pure returns (int128) {
        return int128(BalanceDelta.unwrap(balanceDelta));
    }

    function addAmount0(BalanceDelta balanceDelta, int128 _amount0) internal pure returns (BalanceDelta) {
        return toBalanceDelta(balanceDelta.amount0() + _amount0, balanceDelta.amount1());
    }

    function addAmount1(BalanceDelta balanceDelta, int128 _amount1) internal pure returns (BalanceDelta) {
        return toBalanceDelta(balanceDelta.amount0(), balanceDelta.amount1() + _amount1);
    }

    function subAmount0(BalanceDelta balanceDelta, int128 _amount0) internal pure returns (BalanceDelta) {
        return toBalanceDelta(balanceDelta.amount0() - _amount0, balanceDelta.amount1());
    }

    function subAmount1(BalanceDelta balanceDelta, int128 _amount1) internal pure returns (BalanceDelta) {
        return toBalanceDelta(balanceDelta.amount0(), balanceDelta.amount1() - _amount1);
    }
}
