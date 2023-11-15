// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {BitMath} from "../src/libraries/BitMath.sol";

contract TestBitMath is Test, GasSnapshot {
    function testMostSignificantBitZero() public {
        vm.expectRevert();
        BitMath.mostSignificantBit(0);
    }

    function testMostSignificantBitOne() public {
        assertEq(BitMath.mostSignificantBit(1), 0);
    }

    function testMostSignificantBitTwo() public {
        assertEq(BitMath.mostSignificantBit(2), 1);
    }

    function testMostSignificantBitPowersOfTwo() public {
        for (uint256 i = 0; i < 255; i++) {
            uint256 x = 1 << i;
            assertEq(BitMath.mostSignificantBit(x), i);
        }
    }

    function testMostSignificantBitMaxUint256() public {
        assertEq(BitMath.mostSignificantBit(type(uint256).max), 255);
    }

    function testMostSignificantBit(uint256 x) public {
        vm.assume(x != 0);
        assertEq(BitMath.mostSignificantBit(x), mostSignificantBitReference(x));
    }

    function testMsbGas() public {
        snapStart("BitMathMostSignificantBitSmallNumber");
        BitMath.mostSignificantBit(3568);
        snapEnd();

        snapStart("BitMathMostSignificantBitMaxUint128");
        BitMath.mostSignificantBit(type(uint128).max);
        snapEnd();

        snapStart("BitMathMostSignificantBitMaxUint256");
        BitMath.mostSignificantBit(type(uint256).max);
        snapEnd();
    }

    function testLeastSignificantBitZero() public {
        vm.expectRevert();
        BitMath.leastSignificantBit(0);
    }

    function testLeastSignificantBitOne() public {
        assertEq(BitMath.leastSignificantBit(1), 0);
    }

    function testLeastSignificantBitTwo() public {
        assertEq(BitMath.leastSignificantBit(2), 1);
    }

    function testLeastSignificantBitPowersOfTwo() public {
        for (uint256 i = 0; i < 255; i++) {
            uint256 x = 1 << i;
            assertEq(BitMath.leastSignificantBit(x), i);
        }
    }

    function testLeastSignificantBitMaxUint256() public {
        assertEq(BitMath.leastSignificantBit(type(uint256).max), 0);
    }

    function testLeastSignificantBit(uint256 x) public {
        vm.assume(x != 0);
        assertEq(BitMath.leastSignificantBit(x), leastSignificantBitReference(x));
    }

    function testLsbGas() public {
        snapStart("BitMathLeastSignificantBitSmallNumber");
        BitMath.leastSignificantBit(3568);
        snapEnd();

        snapStart("BitMathLeastSignificantBitMaxUint128");
        BitMath.leastSignificantBit(type(uint128).max);
        snapEnd();

        snapStart("BitMathLeastSignificantBitMaxUint256");
        BitMath.leastSignificantBit(type(uint256).max);
        snapEnd();
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
