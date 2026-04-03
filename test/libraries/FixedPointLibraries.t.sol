// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {FixedPoint96} from "../../src/libraries/FixedPoint96.sol";
import {FixedPoint128} from "../../src/libraries/FixedPoint128.sol";

/// @notice Tests for FixedPoint96 and FixedPoint128 libraries
/// @dev Validates the correctness of the fixed-point constants used throughout Uniswap v4
contract FixedPointLibrariesTest is Test {
    /// @notice Verifies that Q96 equals 2^96
    function test_Q96_value() public pure {
        assertEq(FixedPoint96.Q96, 2 ** 96);
        assertEq(FixedPoint96.Q96, 79228162514264337593543950336);
    }

    /// @notice Verifies that Q128 equals 2^128
    function test_Q128_value() public pure {
        assertEq(FixedPoint128.Q128, 2 ** 128);
        assertEq(FixedPoint128.Q128, 340282366920938463463374607431768211456);
    }

    /// @notice Verifies the RESOLUTION constant for Q96
    function test_Q96_resolution() public pure {
        assertEq(FixedPoint96.RESOLUTION, 96);
        assertEq(FixedPoint96.Q96, 1 << FixedPoint96.RESOLUTION);
    }

    /// @notice Tests that Q96 and Q128 have the expected relationship
    function test_Q96_Q128_relationship() public pure {
        // Q128 should be Q96 * 2^32
        assertEq(FixedPoint128.Q128, FixedPoint96.Q96 * (2 ** 32));
    }

    /// @notice Fuzz test for Q96 fixed-point multiplication and division
    /// @dev Verifies that multiplying by Q96 then dividing returns the original value
    function test_fuzz_Q96_roundtrip(uint160 value) public pure {
        vm.assume(value > 0);
        // Multiply by Q96 and divide should return original
        uint256 scaled = uint256(value) * FixedPoint96.Q96;
        uint256 result = scaled / FixedPoint96.Q96;
        assertEq(result, value);
    }

    /// @notice Fuzz test for Q128 fixed-point multiplication and division
    /// @dev Verifies that multiplying by Q128 then dividing returns the original value
    function test_fuzz_Q128_roundtrip(uint128 value) public pure {
        vm.assume(value > 0);
        // Multiply by Q128 and divide should return original
        uint256 scaled = uint256(value) * FixedPoint128.Q128;
        uint256 result = scaled / FixedPoint128.Q128;
        assertEq(result, value);
    }

    /// @notice Tests Q96 hex representation
    function test_Q96_hex() public pure {
        // Q96 in hex should be 0x1000000000000000000000000 (1 followed by 24 zeros)
        assertEq(FixedPoint96.Q96, 0x1000000000000000000000000);
    }

    /// @notice Tests Q128 hex representation
    function test_Q128_hex() public pure {
        // Q128 in hex should be 0x100000000000000000000000000000000 (1 followed by 32 zeros)
        assertEq(FixedPoint128.Q128, 0x100000000000000000000000000000000);
    }

    /// @notice Tests precision bounds for Q96
    function test_Q96_precision_bounds() public pure {
        // Q96 provides approximately 29 decimal digits of precision
        // This test validates the precision range
        uint256 maxPrecision = type(uint256).max / FixedPoint96.Q96;
        assertTrue(maxPrecision > 0);
        // Ensure Q96 doesn't overflow when used with uint160 (max sqrtPriceX96)
        assertTrue(type(uint160).max < type(uint256).max / FixedPoint96.Q96);
    }

    /// @notice Tests precision bounds for Q128
    function test_Q128_precision_bounds() public pure {
        // Q128 is used for fee growth calculations
        uint256 maxPrecision = type(uint256).max / FixedPoint128.Q128;
        assertTrue(maxPrecision > 0);
        // Ensure Q128 doesn't overflow when used with uint128 (max liquidity)
        assertTrue(type(uint128).max == type(uint256).max / FixedPoint128.Q128);
    }
}
