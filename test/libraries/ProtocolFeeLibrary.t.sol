// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../src/libraries/ProtocolFeeLibrary.sol";
import "../../src/libraries/LPFeeLibrary.sol";
import "forge-std/Test.sol";

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

    function test_validate_fee() public pure {
        uint24 fee = uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE + 1) << 12 | ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
        assertFalse(ProtocolFeeLibrary.validate(fee));

        fee = uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE) << 12 | (ProtocolFeeLibrary.MAX_PROTOCOL_FEE + 1);
        assertFalse(ProtocolFeeLibrary.validate(fee));

        fee = uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE + 1) << 12 | (ProtocolFeeLibrary.MAX_PROTOCOL_FEE + 1);
        assertFalse(ProtocolFeeLibrary.validate(fee));

        fee = uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE) << 12 | ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
        assertTrue(ProtocolFeeLibrary.validate(fee));

        fee = uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE - 1) << 12 | ProtocolFeeLibrary.MAX_PROTOCOL_FEE - 1;
        assertTrue(ProtocolFeeLibrary.validate(fee));

        fee = uint24(0) << 12 | uint24(0);
        assertTrue(ProtocolFeeLibrary.validate(fee));
    }

    function test_fuzz_validate(uint24 fee) public pure {
        if ((fee >> 12 > ProtocolFeeLibrary.MAX_PROTOCOL_FEE) || (fee % 4096 > ProtocolFeeLibrary.MAX_PROTOCOL_FEE)) {
            assertFalse(ProtocolFeeLibrary.validate(fee));
        } else {
            assertTrue(ProtocolFeeLibrary.validate(fee));
        }
    }

    function test_calculateSwapFee() public pure {
        assertEq(
            ProtocolFeeLibrary.calculateSwapFee(uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE), LPFeeLibrary.MAX_LP_FEE),
            LPFeeLibrary.MAX_LP_FEE
        );
        assertEq(ProtocolFeeLibrary.calculateSwapFee(uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE), 3000), 3997);
        assertEq(
            ProtocolFeeLibrary.calculateSwapFee(uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE), 0),
            ProtocolFeeLibrary.MAX_PROTOCOL_FEE
        );
        assertEq(ProtocolFeeLibrary.calculateSwapFee(0, 0), 0);
        assertEq(ProtocolFeeLibrary.calculateSwapFee(0, 1000), 1000);
    }

    function test_fuzz_calculateSwapFee(uint24 self, uint24 lpFee) public pure {
        lpFee = uint24(bound(lpFee, 0, LPFeeLibrary.MAX_LP_FEE));
        self = uint24(bound(self, 0, ProtocolFeeLibrary.MAX_PROTOCOL_FEE));
        // if lp fee is not the max, the swap fee should never be the max since the protocol fee is taken off first and then the lp fee is taken from the remaining amount
        if (lpFee < LPFeeLibrary.MAX_LP_FEE) {
            assertLt(ProtocolFeeLibrary.calculateSwapFee(self, lpFee), LPFeeLibrary.MAX_LP_FEE);
        }
        assertGe(ProtocolFeeLibrary.calculateSwapFee(self, lpFee), lpFee);
    }
}
