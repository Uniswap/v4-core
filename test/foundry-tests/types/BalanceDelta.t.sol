// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {BalanceDelta, toBalanceDelta} from "../../../contracts/types/BalanceDelta.sol";

contract TestBalanceDelta is Test {
    function testToBalanceDelta() public {
        BalanceDelta balanceDelta = toBalanceDelta(0, 0);
        assertEq(balanceDelta.amount0(), 0);
        assertEq(balanceDelta.amount1(), 0);

        balanceDelta = toBalanceDelta(0, 1);
        assertEq(balanceDelta.amount0(), 0);
        assertEq(balanceDelta.amount1(), 1);

        balanceDelta = toBalanceDelta(1, 0);
        assertEq(balanceDelta.amount0(), 1);
        assertEq(balanceDelta.amount1(), 0);

        balanceDelta = toBalanceDelta(-1, -1);
        assertEq(balanceDelta.amount0(), -1);
        assertEq(balanceDelta.amount1(), -1);

        balanceDelta = toBalanceDelta(type(int128).max, type(int128).max);
        assertEq(balanceDelta.amount0(), type(int128).max);
        assertEq(balanceDelta.amount1(), type(int128).max);

        balanceDelta = toBalanceDelta(type(int128).max, 0);
        assertEq(balanceDelta.amount0(), type(int128).max);
        assertEq(balanceDelta.amount1(), 0);

        balanceDelta = toBalanceDelta(0, type(int128).max);
        assertEq(balanceDelta.amount0(), 0);
        assertEq(balanceDelta.amount1(), type(int128).max);

        balanceDelta = toBalanceDelta(type(int128).min, type(int128).min);
        assertEq(balanceDelta.amount0(), type(int128).min);
        assertEq(balanceDelta.amount1(), type(int128).min);

        balanceDelta = toBalanceDelta(type(int128).min, 0);
        assertEq(balanceDelta.amount0(), type(int128).min);
        assertEq(balanceDelta.amount1(), 0);

        balanceDelta = toBalanceDelta(0, type(int128).min);
        assertEq(balanceDelta.amount0(), 0);
        assertEq(balanceDelta.amount1(), type(int128).min);
    }
}
