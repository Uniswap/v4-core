// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {UnsafeMath} from "../../src/libraries/UnsafeMath.sol";

contract UnsafeMathTest is Test {
    using UnsafeMath for uint256;

    uint256 constant Q128 = 2 ** 128;
    uint256 constant MAX_UINT256 = type(uint256).max;

    function test_divRoundingUp_zeroDoesNotRevert(uint256 x) public pure {
        x.divRoundingUp(0);
    }

    function test_divRoundingUp_maxInput() public pure {
        assertEq(MAX_UINT256.divRoundingUp(MAX_UINT256), 1);
    }

    function test_divRoundingUp_RoundsUp() public pure {
        uint256 result = Q128 / 3 + 1;
        assertEq(Q128.divRoundingUp(3), result);
    }

    function test_fuzz_divRoundingUp(uint256 x, uint256 y) public pure {
        vm.assume(y != 0);
        uint256 result = x.divRoundingUp(y);
        assertTrue(result == x / y || result == x / y + 1);
    }

    function test_invariant_divRoundingUp(uint256 x, uint256 y) public pure {
        vm.assume(y != 0);
        uint256 z = x.divRoundingUp(y);
        uint256 diff = z - (x / y);
        if (x % y == 0) {
            assertEq(diff, 0);
        } else {
            assertEq(diff, 1);
        }
    }

    function test_simpleMulDiv_zeroDoesNotRevert(uint256 a, uint256 b) public pure {
        a.simpleMulDiv(b, 0);
    }

    function test_simpleMulDiv_succeeds() public pure {
        assertEq(Q128.simpleMulDiv(3, 2), Q128 * 3 / 2);
    }

    function test_simpleMulDiv_noOverflow() public pure {
        assertLe(uint256(int256(type(int128).max)) * Q128, type(uint256).max);
    }

    function test_fuzz_simpleMulDiv_succeeds(uint256 a, uint256 b, uint256 denominator) public pure {
        vm.assume(denominator != 0);
        uint256 result = a.simpleMulDiv(b, denominator);
        unchecked {
            assertTrue(result == a * b / denominator);
        }
    }

    function test_fuzz_simpleMulDiv_bounded(uint256 a, uint256 denominator) public pure {
        a = bound(a, 0, uint256(int256(type(int128).max)));
        denominator = bound(denominator, 1, uint256(type(uint128).max));
        uint256 result = a.simpleMulDiv(Q128, denominator);
        assertTrue(result == a * Q128 / denominator);
    }
}
