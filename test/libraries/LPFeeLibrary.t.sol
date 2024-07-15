// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../src/libraries/LPFeeLibrary.sol";
import "forge-std/Test.sol";

contract LPFeeLibraryTest is Test {
    function test_isDynamicFee_returnsTrue() public pure {
        uint24 dynamicFee = 0x800000;
        assertTrue(LPFeeLibrary.isDynamicFee(dynamicFee));
    }

    function test_isDynamicFee_returnsFalse_forOtherValues() public pure {
        uint24 dynamicFee = 0xFFFFFF;
        assertFalse(LPFeeLibrary.isDynamicFee(dynamicFee));
        dynamicFee = 0x7FFFFF;
        assertFalse(LPFeeLibrary.isDynamicFee(dynamicFee));
        dynamicFee = 0;
        assertFalse(LPFeeLibrary.isDynamicFee(dynamicFee));
        dynamicFee = 0x800001;
        assertFalse(LPFeeLibrary.isDynamicFee(dynamicFee));
    }

    function test_fuzz_isDynamicFee(uint24 fee) public pure {
        assertEq(fee == LPFeeLibrary.DYNAMIC_FEE_FLAG, LPFeeLibrary.isDynamicFee(fee));
    }

    function test_validate_doesNotRevertWithNoFee() public pure {
        uint24 fee = 0;
        LPFeeLibrary.validate(fee);
    }

    function test_validate_doesNotRevert() public pure {
        uint24 fee = 500000; // 50%
        LPFeeLibrary.validate(fee);
    }

    function test_validate_doesNotRevertWithMaxFee() public pure {
        uint24 maxFee = 1000000; // 100%
        LPFeeLibrary.validate(maxFee);
    }

    function test_validate_revertsWithLPFeeTooLarge() public {
        uint24 fee = 1000001;
        vm.expectRevert(abi.encodeWithSelector(LPFeeLibrary.LPFeeTooLarge.selector, fee));
        LPFeeLibrary.validate(fee);
    }

    function test_fuzz_validate(uint24 fee) public {
        if (fee > 1000000) {
            vm.expectRevert(abi.encodeWithSelector(LPFeeLibrary.LPFeeTooLarge.selector, fee));
        }
        LPFeeLibrary.validate(fee);
    }

    function test_getInitialLPFee_forStaticFeeIsCorrect() public pure {
        uint24 staticFee = 3000; // 30 bps
        assertEq(LPFeeLibrary.getInitialLPFee(staticFee), staticFee);
    }

    function test_getInitialLPFee_revertsWithLPFeeTooLarge_forStaticFee() public {
        uint24 staticFee = 1000001;
        vm.expectRevert(abi.encodeWithSelector(LPFeeLibrary.LPFeeTooLarge.selector, staticFee));
        LPFeeLibrary.getInitialLPFee(staticFee);
    }

    function test_getInitialLPFee_forDynamicFeeIsZero() public pure {
        uint24 dynamicFee = 0x800000;
        assertEq(LPFeeLibrary.getInitialLPFee(dynamicFee), 0);
    }

    function test_getInitialLpFee_revertsWithNonExactDynamicFee() public {
        uint24 dynamicFee = 0x800001;
        vm.expectRevert(abi.encodeWithSelector(LPFeeLibrary.LPFeeTooLarge.selector, dynamicFee));
        LPFeeLibrary.getInitialLPFee(dynamicFee);
    }

    function test_fuzz_getInitialLPFee(uint24 fee) public {
        if (fee == LPFeeLibrary.DYNAMIC_FEE_FLAG) {
            assertEq(LPFeeLibrary.getInitialLPFee(fee), 0);
        } else if (fee > 1000000) {
            vm.expectRevert(abi.encodeWithSelector(LPFeeLibrary.LPFeeTooLarge.selector, fee));
            LPFeeLibrary.getInitialLPFee(fee);
        } else {
            assertEq(LPFeeLibrary.getInitialLPFee(fee), fee);
        }
    }
}
