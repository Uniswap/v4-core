// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {SafeCast} from "src/libraries/SafeCast.sol";
import {LiquidityMathTest as LiquidityMath} from "src/test/LiquidityMathTest.sol";

contract LiquidityMathRef {
    function addDelta(uint128 x, int128 y) external pure returns (uint128) {
        return y < 0 ? x - uint128(-y) : x + uint128(y);
    }
}

contract LiquidityMathTest is Test {
    LiquidityMath internal liquidityMath;
    LiquidityMathRef internal liquidityMathRef;

    function setUp() public {
        liquidityMath = new LiquidityMath();
        liquidityMathRef = new LiquidityMathRef();
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

    function test_addDelta_sub_int128min_throwsForReferenceOnly() public {
        assertEq(liquidityMath.addDelta(uint128(type(int128).min), type(int128).min), 0);
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        liquidityMathRef.addDelta(uint128(type(int128).min), type(int128).min);
    }

    function test_addDelta_sub_int128min_fuzz(uint128 x) public view {
        x = uint128(bound(x, uint128(type(int128).min), type(uint128).max));
        assertEq(liquidityMath.addDelta(x, type(int128).min), x - uint128(type(int128).min));
    }

    /// @notice Test the equivalence of the new `addDelta` and the reference implementation
    function test_addDelta_fuzz(uint128 x, int128 y) public {
        vm.assume(y != type(int128).min);
        try liquidityMath.addDelta(x, y) returns (uint128 z) {
            assertEq(z, liquidityMathRef.addDelta(x, y));
        } catch (bytes memory reason) {
            assertEq(bytes4(reason), SafeCast.SafeCastOverflow.selector);
            vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
            liquidityMathRef.addDelta(x, y);
        }
    }
}
