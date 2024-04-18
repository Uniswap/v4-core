// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "src/libraries/ProtocolFeeLibrary.sol";
import "src/libraries/SwapFeeLibrary.sol";
import "forge-std/Test.sol";

contract ProtocolFeeLibraryTest is Test {
    function test_zeroForOne() public {
        uint24 fee = uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE) << 12 | ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
        assertEq(ProtocolFeeLibrary.getZeroForOneFee(fee), uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE));
    }

    function test_oneForZero() public {
        uint24 fee = uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE) << 12 | ProtocolFeeLibrary.MAX_PROTOCOL_FEE;
        assertEq(ProtocolFeeLibrary.getOneForZeroFee(fee), uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE));
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

    function test_fuzz_calculateEffectiveFeeDoesNotOverflow(uint24 self, uint24 swapFee) public {
        swapFee = uint24(bound(swapFee, 0, SwapFeeLibrary.MAX_SWAP_FEE));
        self = uint24(bound(self, 0, ProtocolFeeLibrary.MAX_PROTOCOL_FEE));
        assertGe(ProtocolFeeLibrary.calculateEffectiveFee(self, swapFee), swapFee);
    }

    function test_fuzz_calculateEffectiveFeeNeverEqualsMax(uint24 self, uint24 swapFee) public {
        swapFee = uint24(bound(swapFee, 0, SwapFeeLibrary.MAX_SWAP_FEE - 1));
        self = uint24(bound(self, 0, ProtocolFeeLibrary.MAX_PROTOCOL_FEE));
        assertLt(ProtocolFeeLibrary.calculateEffectiveFee(self, swapFee), SwapFeeLibrary.MAX_SWAP_FEE);
    }

    function test_calculateEffectiveFee() public {
        uint24 self = uint24(ProtocolFeeLibrary.MAX_PROTOCOL_FEE);
        uint24 swapFee = SwapFeeLibrary.MAX_SWAP_FEE;
        assertEq(ProtocolFeeLibrary.calculateEffectiveFee(self, swapFee), SwapFeeLibrary.MAX_SWAP_FEE);

        swapFee = 3000;
        assertEq(ProtocolFeeLibrary.calculateEffectiveFee(self, swapFee), 3997);

        swapFee = 0;
        assertEq(ProtocolFeeLibrary.calculateEffectiveFee(self, swapFee), ProtocolFeeLibrary.MAX_PROTOCOL_FEE);

        self = 0;
        assertEq(ProtocolFeeLibrary.calculateEffectiveFee(self, swapFee), 0);

        swapFee = 1000;
        assertEq(ProtocolFeeLibrary.calculateEffectiveFee(self, swapFee), 1000);
    }
}
