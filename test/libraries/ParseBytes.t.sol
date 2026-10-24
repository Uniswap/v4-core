// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ParseBytes} from "../../src/libraries/ParseBytes.sol";

contract ParseBytesTest is Test {
    using ParseBytes for bytes;

    function test_parseSelector_returnsFirstFourBytes() public pure {
        bytes4 expectedSelector = bytes4(keccak256("someFunction(uint256)"));
        bytes memory data = abi.encode(expectedSelector, int256(0));
        assertEq(ParseBytes.parseSelector(data), expectedSelector);
    }

    function test_parseSelector_withNonZeroDelta() public pure {
        bytes4 expectedSelector = bytes4(0xdeadbeef);
        bytes memory data = abi.encode(expectedSelector, int256(12345));
        assertEq(ParseBytes.parseSelector(data), expectedSelector);
    }

    function test_fuzz_parseSelector(bytes4 selector, int256 delta) public pure {
        bytes memory data = abi.encode(selector, delta);
        assertEq(ParseBytes.parseSelector(data), selector);
    }

    function test_parseReturnDelta_returnsSecondWord() public pure {
        bytes4 selector = bytes4(0x12345678);
        int256 expectedDelta = -999;
        bytes memory data = abi.encode(selector, expectedDelta);
        assertEq(ParseBytes.parseReturnDelta(data), expectedDelta);
    }

    function test_parseReturnDelta_zero() public pure {
        bytes memory data = abi.encode(bytes4(0xaabbccdd), int256(0));
        assertEq(ParseBytes.parseReturnDelta(data), 0);
    }

    function test_parseReturnDelta_maxPositive() public pure {
        bytes memory data = abi.encode(bytes4(0x00000000), type(int256).max);
        assertEq(ParseBytes.parseReturnDelta(data), type(int256).max);
    }

    function test_parseReturnDelta_minNegative() public pure {
        bytes memory data = abi.encode(bytes4(0x00000000), type(int256).min);
        assertEq(ParseBytes.parseReturnDelta(data), type(int256).min);
    }

    function test_fuzz_parseReturnDelta(bytes4 selector, int256 delta) public pure {
        bytes memory data = abi.encode(selector, delta);
        assertEq(ParseBytes.parseReturnDelta(data), delta);
    }

    function test_parseFee_returnsThirdWord() public pure {
        bytes4 selector = bytes4(0x12345678);
        int256 delta = 100;
        uint24 expectedFee = 3000;
        bytes memory data = abi.encode(selector, delta, expectedFee);
        assertEq(ParseBytes.parseFee(data), expectedFee);
    }

    function test_parseFee_maxFee() public pure {
        uint24 maxFee = type(uint24).max; // 16777215
        bytes memory data = abi.encode(bytes4(0x00000000), int256(0), maxFee);
        assertEq(ParseBytes.parseFee(data), maxFee);
    }

    function test_parseFee_zeroFee() public pure {
        bytes memory data = abi.encode(bytes4(0x00000000), int256(0), uint24(0));
        assertEq(ParseBytes.parseFee(data), 0);
    }

    function test_fuzz_parseFee(bytes4 selector, int256 delta, uint24 fee) public pure {
        bytes memory data = abi.encode(selector, delta, fee);
        assertEq(ParseBytes.parseFee(data), fee);
    }

    function test_parseSelector_and_parseReturnDelta_consistent() public pure {
        bytes4 selector = bytes4(0xaabbccdd);
        int256 delta = -42;
        bytes memory data = abi.encode(selector, delta);
        assertEq(ParseBytes.parseSelector(data), selector);
        assertEq(ParseBytes.parseReturnDelta(data), delta);
    }

    function test_allThreeFields_consistent() public pure {
        bytes4 selector = bytes4(0x11223344);
        int256 delta = 500;
        uint24 fee = 10000;
        bytes memory data = abi.encode(selector, delta, fee);
        assertEq(ParseBytes.parseSelector(data), selector);
        assertEq(ParseBytes.parseReturnDelta(data), delta);
        assertEq(ParseBytes.parseFee(data), fee);
    }

    function test_fuzz_allThreeFields(bytes4 selector, int256 delta, uint24 fee) public pure {
        bytes memory data = abi.encode(selector, delta, fee);
        assertEq(ParseBytes.parseSelector(data), selector);
        assertEq(ParseBytes.parseReturnDelta(data), delta);
        assertEq(ParseBytes.parseFee(data), fee);
    }
}
