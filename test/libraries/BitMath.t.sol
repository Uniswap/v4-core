// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {BitMath} from "../../src/libraries/BitMath.sol";

contract TestBitMath is Test {
    function test_mostSignificantBit_revertsWhenZero() public {
        vm.expectRevert();
        BitMath.mostSignificantBit(0);
    }

    function test_mostSignificantBit_one() public pure {
        assertEq(BitMath.mostSignificantBit(1), 0);
    }

    function test_mostSignificantBit_two() public pure {
        assertEq(BitMath.mostSignificantBit(2), 1);
    }

    function test_mostSignificantBit_powersOfTwo() public pure {
        for (uint256 i = 0; i < 255; i++) {
            uint256 x = 1 << i;
            assertEq(BitMath.mostSignificantBit(x), i);
        }
    }

    function test_mostSignificantBit_maxUint256() public pure {
        assertEq(BitMath.mostSignificantBit(type(uint256).max), 255);
    }

    function test_fuzz_mostSignificantBit(uint256 x) public pure {
        vm.assume(x != 0);
        assertEq(BitMath.mostSignificantBit(x), mostSignificantBitReference(x));
    }

    function test_invariant_mostSignificantBit(uint256 x) public pure {
        vm.assume(x != 0);
        uint8 msb = BitMath.mostSignificantBit(x);
        assertGe(x, uint256(2) ** msb);
        assertTrue(msb == 255 || x < uint256(2) ** (msb + 1));
    }

    function test_mostSignificantBit_gas() public {
        vm.startSnapshotGas("BitMathMostSignificantBitSmallNumber");
        BitMath.mostSignificantBit(3568);
        vm.stopSnapshotGas();

        vm.startSnapshotGas("BitMathMostSignificantBitMaxUint128");
        BitMath.mostSignificantBit(type(uint128).max);
        vm.stopSnapshotGas();

        vm.startSnapshotGas("BitMathMostSignificantBitMaxUint256");
        BitMath.mostSignificantBit(type(uint256).max);
        vm.stopSnapshotGas();
    }

    function test_leastSignificantBit_revertsWhenZero() public {
        vm.expectRevert();
        BitMath.leastSignificantBit(0);
    }

    function test_leastSignificantBit_one() public pure {
        assertEq(BitMath.leastSignificantBit(1), 0);
    }

    function test_leastSignificantBit_two() public pure {
        assertEq(BitMath.leastSignificantBit(2), 1);
    }

    function test_leastSignificantBit_powersOfTwo() public pure {
        for (uint256 i = 0; i < 255; i++) {
            uint256 x = 1 << i;
            assertEq(BitMath.leastSignificantBit(x), i);
        }
    }

    function test_leastSignificantBit_maxUint256() public pure {
        assertEq(BitMath.leastSignificantBit(type(uint256).max), 0);
    }

    function test_fuzz_leastSignificantBit(uint256 x) public pure {
        vm.assume(x != 0);
        assertEq(BitMath.leastSignificantBit(x), leastSignificantBitReference(x));
    }

    function test_invariant_leastSignificantBit(uint256 x) public pure {
        vm.assume(x != 0);
        uint8 lsb = BitMath.leastSignificantBit(x);
        assertNotEq(x & (uint256(2) ** lsb), 0);
        assertEq(x & (uint256(2) ** lsb - 1), 0);
    }

    function test_leastSignificantBit_gas() public {
        vm.startSnapshotGas("BitMathLeastSignificantBitSmallNumber");
        BitMath.leastSignificantBit(3568);
        vm.stopSnapshotGas();

        vm.startSnapshotGas("BitMathLeastSignificantBitMaxUint128");
        BitMath.leastSignificantBit(type(uint128).max);
        vm.stopSnapshotGas();

        vm.startSnapshotGas("BitMathLeastSignificantBitMaxUint256");
        BitMath.leastSignificantBit(type(uint256).max);
        vm.stopSnapshotGas();
    }

    function mostSignificantBitReference(uint256 x) private pure returns (uint256) {
        uint256 i = 0;
        while ((x >>= 1) > 0) {
            ++i;
        }
        return i;
    }

    function leastSignificantBitReference(uint256 x) private pure returns (uint256) {
        require(x > 0, "BitMath: zero has no least significant bit");

        uint256 i = 0;
        while ((x >> i) & 1 == 0) {
            ++i;
        }
        return i;
    }
}
