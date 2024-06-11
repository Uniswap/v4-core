// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {BalanceDeltas, toBalanceDeltas} from "../../src/types/BalanceDeltas.sol";

contract TestBalanceDeltas is Test {
    function test_toBalanceDeltas() public pure {
        BalanceDeltas balanceDeltas = toBalanceDeltas(0, 0);
        assertEq(balanceDeltas.amount0(), 0);
        assertEq(balanceDeltas.amount1(), 0);

        balanceDeltas = toBalanceDeltas(0, 1);
        assertEq(balanceDeltas.amount0(), 0);
        assertEq(balanceDeltas.amount1(), 1);

        balanceDeltas = toBalanceDeltas(1, 0);
        assertEq(balanceDeltas.amount0(), 1);
        assertEq(balanceDeltas.amount1(), 0);

        balanceDeltas = toBalanceDeltas(type(int128).max, type(int128).max);
        assertEq(balanceDeltas.amount0(), type(int128).max);
        assertEq(balanceDeltas.amount1(), type(int128).max);

        balanceDeltas = toBalanceDeltas(type(int128).min, type(int128).min);
        assertEq(balanceDeltas.amount0(), type(int128).min);
        assertEq(balanceDeltas.amount1(), type(int128).min);
    }

    function test_fuzz_toBalanceDeltas(int128 x, int128 y) public pure {
        BalanceDeltas balanceDeltas = toBalanceDeltas(x, y);
        int256 expectedBD = int256(uint256(bytes32(abi.encodePacked(x, y))));
        assertEq(BalanceDeltas.unwrap(balanceDeltas), expectedBD);
    }

    function test_fuzz_amount0_amount1(int128 x, int128 y) public pure {
        BalanceDeltas balanceDeltas = toBalanceDeltas(x, y);
        assertEq(balanceDeltas.amount0(), x);
        assertEq(balanceDeltas.amount1(), y);
    }

    function test_add() public pure {
        BalanceDeltas balanceDeltas = toBalanceDeltas(0, 0) + toBalanceDeltas(0, 0);
        assertEq(balanceDeltas.amount0(), 0);
        assertEq(balanceDeltas.amount1(), 0);

        balanceDeltas = toBalanceDeltas(-1000, 1000) + toBalanceDeltas(1000, -1000);
        assertEq(balanceDeltas.amount0(), 0);
        assertEq(balanceDeltas.amount1(), 0);

        balanceDeltas =
            toBalanceDeltas(type(int128).min, type(int128).max) + toBalanceDeltas(type(int128).max, type(int128).min);
        assertEq(balanceDeltas.amount0(), -1);
        assertEq(balanceDeltas.amount1(), -1);

        balanceDeltas = toBalanceDeltas(type(int128).max / 2 + 1, type(int128).max / 2 + 1)
            + toBalanceDeltas(type(int128).max / 2, type(int128).max / 2);
        assertEq(balanceDeltas.amount0(), type(int128).max);
        assertEq(balanceDeltas.amount1(), type(int128).max);
    }

    function test_add_revertsOnOverflow() public {
        // should revert because type(int128).max + 1 is not possible
        vm.expectRevert();
        toBalanceDeltas(type(int128).max, 0) + toBalanceDeltas(1, 0);

        vm.expectRevert();
        toBalanceDeltas(0, type(int128).max) + toBalanceDeltas(0, 1);
    }

    function test_fuzz_add(int128 a, int128 b, int128 c, int128 d) public {
        int256 ac = int256(a) + c;
        int256 bd = int256(b) + d;

        // if the addition overflows it should revert
        if (ac != int128(ac) || bd != int128(bd)) {
            vm.expectRevert();
        }

        BalanceDeltas balanceDeltas = toBalanceDeltas(a, b) + toBalanceDeltas(c, d);
        assertEq(balanceDeltas.amount0(), ac);
        assertEq(balanceDeltas.amount1(), bd);
    }

    function test_sub() public pure {
        BalanceDeltas balanceDeltas = toBalanceDeltas(0, 0) - toBalanceDeltas(0, 0);
        assertEq(balanceDeltas.amount0(), 0);
        assertEq(balanceDeltas.amount1(), 0);

        balanceDeltas = toBalanceDeltas(-1000, 1000) - toBalanceDeltas(1000, -1000);
        assertEq(balanceDeltas.amount0(), -2000);
        assertEq(balanceDeltas.amount1(), 2000);

        balanceDeltas =
            toBalanceDeltas(-1000, -1000) - toBalanceDeltas(-(type(int128).min + 1000), -(type(int128).min + 1000));
        assertEq(balanceDeltas.amount0(), type(int128).min);
        assertEq(balanceDeltas.amount1(), type(int128).min);

        balanceDeltas = toBalanceDeltas(type(int128).min / 2, type(int128).min / 2)
            - toBalanceDeltas(-(type(int128).min / 2), -(type(int128).min / 2));
        assertEq(balanceDeltas.amount0(), type(int128).min);
        assertEq(balanceDeltas.amount1(), type(int128).min);
    }

    function test_sub_revertsOnUnderflow() public {
        // should revert because type(int128).min - 1 is not possible
        vm.expectRevert();
        toBalanceDeltas(type(int128).min, 0) - toBalanceDeltas(1, 0);

        vm.expectRevert();
        toBalanceDeltas(0, type(int128).min) - toBalanceDeltas(0, 1);
    }

    function test_fuzz_sub(int128 a, int128 b, int128 c, int128 d) public {
        int256 ac = int256(a) - c;
        int256 bd = int256(b) - d;

        // if the subtraction underflows it should revert
        if (ac != int128(ac) || bd != int128(bd)) {
            vm.expectRevert();
        }

        BalanceDeltas balanceDeltas = toBalanceDeltas(a, b) - toBalanceDeltas(c, d);
        assertEq(balanceDeltas.amount0(), ac);
        assertEq(balanceDeltas.amount1(), bd);
    }

    function test_fuzz_eq(int128 a, int128 b, int128 c, int128 d) public pure {
        bool isEqual = (toBalanceDeltas(a, b) == toBalanceDeltas(c, d));
        if (a == c && b == d) assertTrue(isEqual);
        else assertFalse(isEqual);
    }

    function test_fuzz_neq(int128 a, int128 b, int128 c, int128 d) public pure {
        bool isNotEqual = (toBalanceDeltas(a, b) != toBalanceDeltas(c, d));
        if (a != c || b != d) assertTrue(isNotEqual);
        else assertFalse(isNotEqual);
    }
}
