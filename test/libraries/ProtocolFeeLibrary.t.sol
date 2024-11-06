// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {LPFeeLibrary} from "../../src/libraries/LPFeeLibrary.sol";
import {ProtocolFeeLibrary} from "../../src/libraries/ProtocolFeeLibrary.sol";

contract ProtocolFeeLibraryTest is Test {
    function test_getZeroForOneFee() public pure {
        uint24 fee = uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE - 1) << 12 | ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
        assertEq(ProtocolFeeLibrary.getZeroForOneFee(fee), uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE));
    }

    function test_fuzz_getZeroForOneFee(uint24 fee) public pure {
        assertEq(ProtocolFeeLibrary.getZeroForOneFee(fee), fee % 4096);
    }

    function test_getOneForZeroFee() public pure {
        uint24 fee = uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE - 1) << 12 | ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
        assertEq(ProtocolFeeLibrary.getOneForZeroFee(fee), uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE - 1));
    }

    function test_fuzz_getOneForZeroFee(uint24 fee) public pure {
        assertEq(ProtocolFeeLibrary.getOneForZeroFee(fee), fee >> 12);
    }

    function test_isValidProtocolFee_fee() public pure {
        uint24 fee = uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE + 1) << 12 | ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
        assertFalse(ProtocolFeeLibrary.isValidProtocolFee(fee));

        fee = uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE) << 12 | (ProtocolFeeLibrary.MAX_PROTOCOL_FEE + 1);
        assertFalse(ProtocolFeeLibrary.isValidProtocolFee(fee));

        fee = uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE + 1) << 12 | (ProtocolFeeLibrary.MAX_PROTOCOL_FEE + 1);
        assertFalse(ProtocolFeeLibrary.isValidProtocolFee(fee));

        fee = uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE) << 12 | ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
        assertTrue(ProtocolFeeLibrary.isValidProtocolFee(fee));

        fee = uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE - 1) << 12 | ProtocolFeeLibrary.MAX_PROTOCOL_FEE - 1;
        assertTrue(ProtocolFeeLibrary.isValidProtocolFee(fee));

        fee = uint24(0) << 12 | uint24(0);
        assertTrue(ProtocolFeeLibrary.isValidProtocolFee(fee));
    }

    function test_fuzz_isValidProtocolFee(uint24 fee) public pure {
        if ((fee >> 12 > ProtocolFeeLibrary.MAX_PROTOCOL_FEE) || (fee % 4096 > ProtocolFeeLibrary.MAX_PROTOCOL_FEE)) {
            assertFalse(ProtocolFeeLibrary.isValidProtocolFee(fee));
        } else {
            assertTrue(ProtocolFeeLibrary.isValidProtocolFee(fee));
        }
    }

    function test_calculateSwapFee() public pure {
        assertEq(
            ProtocolFeeLibrary.calculateSwapFee(uint16(ProtocolFeeLibrary.MAX_PROTOCOL_FEE), LPFeeLibrary.MAX_LP_FEE),
            LPFeeLibrary.MAX_LP_FEE
        );
        assertEq(ProtocolFeeLibrary.calculateSwapFee(uint16(ProtocolFeeLibrary.MAX_PROTOCOL_FEE), 3000), 3997);
        assertEq(
            ProtocolFeeLibrary.calculateSwapFee(uint16(ProtocolFeeLibrary.MAX_PROTOCOL_FEE), 0),
            ProtocolFeeLibrary.MAX_PROTOCOL_FEE
        );
        assertEq(ProtocolFeeLibrary.calculateSwapFee(0, 0), 0);
        assertEq(ProtocolFeeLibrary.calculateSwapFee(0, 1000), 1000);
    }

    function test_fuzz_calculateSwapFee(uint16 protocolFee, uint24 lpFee) public pure {
        protocolFee = uint16(bound(protocolFee, 0, ProtocolFeeLibrary.MAX_PROTOCOL_FEE));
        lpFee = uint24(bound(lpFee, 0, LPFeeLibrary.MAX_LP_FEE));
        uint24 swapFee = ProtocolFeeLibrary.calculateSwapFee(protocolFee, lpFee);
        if (lpFee < LPFeeLibrary.MAX_LP_FEE) {
            assertLe(swapFee, LPFeeLibrary.MAX_LP_FEE);
        } else {
            // if lp fee is equal to max, swap fee can never be larger
            assertEq(swapFee, LPFeeLibrary.MAX_LP_FEE);
        }

        // protocolFee + lpFee(1_000_000 - protocolFee) / 1_000_000 (rounded up)
        uint256 expectedSwapFee = protocolFee + (1e6 - protocolFee) * uint256(lpFee) / 1e6;
        if (((1e6 - protocolFee) * uint256(lpFee)) % 1e6 != 0) expectedSwapFee++;

        assertGe(swapFee, lpFee);
        assertEq(swapFee, uint24(expectedSwapFee));
    }
}
