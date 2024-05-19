// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {SafeCast} from "../../src/libraries/SafeCast.sol";
import {LiquidityMath} from "../../src/libraries/LiquidityMath.sol";
import {LiquidityMathTest as LiquidityMathMock} from "../../src/test/LiquidityMathTest.sol";

contract LiquidityMathRef {
    function addDelta(uint128 x, int128 y) external pure returns (uint128) {
        return y < 0 ? x - uint128(-y) : x + uint128(y);
    }
}

contract LiquidityMathTest is Test {
    uint128 internal constant NEG_INT128_MIN = uint128(type(int128).min);

    LiquidityMathMock internal liquidityMath;
    LiquidityMathRef internal liquidityMathRef;

    function setUp() public {
        liquidityMath = new LiquidityMathMock();
        liquidityMathRef = new LiquidityMathRef();
        assertEq(NEG_INT128_MIN, 1 << 127);
    }

    /// @notice Test the revert reason for underflow
    function test_addDelta_throwsForUnderflow() public {
        vm.expectRevert(SafeCast.SafeCastOverflow.selector);
        liquidityMath.addDelta(0, -1);
        vm.expectRevert(SafeCast.SafeCastOverflow.selector);
        liquidityMath.addDelta(uint128(type(int128).max), type(int128).min);
    }

    /// @notice Test the revert reason for overflow
    function test_addDelta_throwsForOverflow() public {
        vm.expectRevert(SafeCast.SafeCastOverflow.selector);
        liquidityMath.addDelta(type(uint128).max, 1);
    }

    /// @notice Test the ternary expression reverts when subtracting `type(int128).min`
    function test_addDelta_sub_int128min_throwsForReferenceOnly() public {
        assertEq(liquidityMath.addDelta(NEG_INT128_MIN, type(int128).min), 0);
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        liquidityMathRef.addDelta(NEG_INT128_MIN, type(int128).min);
    }

    /// @notice Test the assembly implementation of `addDelta` with `type(int128).min`
    function test_fuzz_addDelta_sub_int128min(uint128 x) public {
        if (x < NEG_INT128_MIN) {
            vm.expectRevert(SafeCast.SafeCastOverflow.selector);
            liquidityMath.addDelta(x, type(int128).min);
        } else {
            assertEq(liquidityMath.addDelta(x, type(int128).min), x - NEG_INT128_MIN);
        }
    }

    /// @notice Test the equivalence of `addDelta` and the reference implementation
    function test_fuzz_addDelta(uint128 x, int128 y) public {
        vm.assume(y != type(int128).min);
        try liquidityMath.addDelta(x, y) returns (uint128 z) {
            assertEq(z, liquidityMathRef.addDelta(x, y));
        } catch (bytes memory reason) {
            assertEq(bytes4(reason), SafeCast.SafeCastOverflow.selector);
            vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
            liquidityMathRef.addDelta(x, y);
        }
    }

    /// @notice Test `flipLiquidityDelta` against the ternary expression
    function test_fuzz_flipLiquidityDelta(int128 liquidityDelta, bool flip) public pure {
        assertEq(
            LiquidityMath.flipLiquidityDelta(liquidityDelta, flip),
            flip ? -int256(liquidityDelta) : int256(liquidityDelta)
        );
    }

    /// @notice Test the usage of `flipLiquidityDelta` on `type(int128).min` followed by `addDelta`
    function test_fuzz_flipLiquidityDelta_int128min(uint128 liquidity) public {
        int256 liquidityNet = LiquidityMath.flipLiquidityDelta(type(int128).min, true);
        assertEq(liquidityNet, 1 << 127);
        // soft wrap to int128
        int128 liquidityNet128 = int128(liquidityNet);
        // implicit upcast to int256 involves sign extension
        assertEq(liquidityNet128, type(int128).min);
        int256 _liquidityNet;
        assembly {
            // direct stack assignment
            _liquidityNet := liquidityNet128
        }
        // verify the content remains the same
        assertEq(_liquidityNet, 1 << 127);
        if (liquidity < 1 << 127) {
            // verify the soft wrap to int128 is passed truthfully without sign extension
            assertEq(LiquidityMath.addDelta(liquidity, int128(liquidityNet)), liquidity + (1 << 127));
        } else {
            vm.expectRevert(SafeCast.SafeCastOverflow.selector);
            LiquidityMath.addDelta(liquidity, int128(liquidityNet));
        }
    }
}
