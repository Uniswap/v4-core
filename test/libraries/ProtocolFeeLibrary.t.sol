// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "src/libraries/ProtocolFeeLibrary.sol";
import "src/libraries/LPFeeLibrary.sol";
import "forge-std/Test.sol";

contract ProtocolFeeLibraryTest is Test {
    function test_zeroForOne() public {
        uint24 fee = uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE - 1) << 12 | ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
        assertEq(ProtocolFeeLibrary.getZeroForOneFee(fee), uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE));
    }

    function test_oneForZero() public {
        uint24 fee = uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE - 1) << 12 | ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
        assertEq(ProtocolFeeLibrary.getOneForZeroFee(fee), uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE - 1));
    }

    function test_fuzz_validate_protocolFee(uint24 fee) public {
        if (
            (fee >> 12 > ProtocolFeeLibrary.MAX_PROTOCOL_FEE)
                || (fee & (4096 - 1) > ProtocolFeeLibrary.MAX_PROTOCOL_FEE)
        ) {
            assertFalse(ProtocolFeeLibrary.validate(fee));
        } else {
            assertTrue(ProtocolFeeLibrary.validate(fee));
        }
    }

    function test_validate() public {
        uint24 fee = uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE + 1) << 12 | ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
        assertFalse(ProtocolFeeLibrary.validate(fee));

        fee = uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE) << 12 | (ProtocolFeeLibrary.MAX_PROTOCOL_FEE + 1);
        assertFalse(ProtocolFeeLibrary.validate(fee));

        fee = uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE + 1) << 12 | (ProtocolFeeLibrary.MAX_PROTOCOL_FEE + 1);
        assertFalse(ProtocolFeeLibrary.validate(fee));

        fee = uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE) << 12 | ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
        assertTrue(ProtocolFeeLibrary.validate(fee));
    }

    function test_fuzz_calculateSwapFeeDoesNotOverflow(uint24 self, uint24 lpFee) public {
        lpFee = uint24(bound(lpFee, 0, LPFeeLibrary.MAX_LP_FEE));
        self = uint24(bound(self, 0, ProtocolFeeLibrary.MAX_PROTOCOL_FEE));
        assertGe(ProtocolFeeLibrary.calculateSwapFee(self, lpFee), lpFee);
    }

    function test_fuzz_calculateSwapFeeNeverEqualsMax(uint24 self, uint24 lpFee) public {
        lpFee = uint24(bound(lpFee, 0, LPFeeLibrary.MAX_LP_FEE - 1));
        self = uint24(bound(self, 0, ProtocolFeeLibrary.MAX_PROTOCOL_FEE));
        assertLt(ProtocolFeeLibrary.calculateSwapFee(self, lpFee), LPFeeLibrary.MAX_LP_FEE);
    }

    function test_calculateSwapFee() public {
        uint24 self = uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE);
        uint24 lpFee = LPFeeLibrary.MAX_LP_FEE;
        assertEq(ProtocolFeeLibrary.calculateSwapFee(self, lpFee), LPFeeLibrary.MAX_LP_FEE);

        lpFee = 3000;
        assertEq(ProtocolFeeLibrary.calculateSwapFee(self, lpFee), 3997);

        lpFee = 0;
        assertEq(ProtocolFeeLibrary.calculateSwapFee(self, lpFee), ProtocolFeeLibrary.MAX_PROTOCOL_FEE);

        self = 0;
        assertEq(ProtocolFeeLibrary.calculateSwapFee(self, lpFee), 0);

        lpFee = 1000;
        assertEq(ProtocolFeeLibrary.calculateSwapFee(self, lpFee), 1000);
    }
}
