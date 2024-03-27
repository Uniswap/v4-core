// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "src/libraries/SwapFeeLibrary.sol";
import "forge-std/Test.sol";

contract SwapFeeLibraryTest is Test {
    function test_isDynamicFee_returnsTrue() public {
        uint24 dynamicFee = 0x800000;
        assertTrue(SwapFeeLibrary.isDynamicFee(dynamicFee));
    }

    function test_isDynamicFee_returnsTrue_forMaxValue() public {
        uint24 dynamicFee = 0xFFFFFF;
        assertTrue(SwapFeeLibrary.isDynamicFee(dynamicFee));
    }

    function test_isDynamicFee_returnsFalse() public {
        uint24 dynamicFee = 0x7FFFFF;
        assertFalse(SwapFeeLibrary.isDynamicFee(dynamicFee));
    }

    function test_fuzz_isDynamicFee(uint24 fee) public {
        assertEq((fee >> 23 == 1), SwapFeeLibrary.isDynamicFee(fee));
    }

    function test_validate_doesNotRevertWithNoFee() public pure {
        uint24 fee = 0;
        SwapFeeLibrary.validate(fee);
    }

    function test_validate_doesNotRevert() public pure {
        uint24 fee = 500000; // 50%
        SwapFeeLibrary.validate(fee);
    }

    function test_validate_doesNotRevertWithMaxFee() public pure {
        uint24 maxFee = 1000000; // 100%
        SwapFeeLibrary.validate(maxFee);
    }

    function test_validate_revertsWithFeeTooLarge() public {
        uint24 fee = 1000001;
        vm.expectRevert(SwapFeeLibrary.FeeTooLarge.selector);
        SwapFeeLibrary.validate(fee);
    }

    function test_fuzz_validate(uint24 fee) public {
        if (fee > 1000000) {
            vm.expectRevert(SwapFeeLibrary.FeeTooLarge.selector);
        }
        SwapFeeLibrary.validate(fee);
    }

    function test_getInitialSwapFee_forStaticFeeIsCorrect() public {
        uint24 staticFee = 3000; // 30 bps
        assertEq(SwapFeeLibrary.getInitialSwapFee(staticFee), staticFee);
    }

    function test_getInitialSwapFee_revertsWithFeeTooLarge_forStaticFee() public {
        uint24 staticFee = 1000001;
        vm.expectRevert(SwapFeeLibrary.FeeTooLarge.selector);
        SwapFeeLibrary.getInitialSwapFee(staticFee);
    }

    function test_getInitialSwapFee_forDynamicFeeIsZero() public {
        uint24 dynamicFee = 0x800BB8;
        assertEq(SwapFeeLibrary.getInitialSwapFee(dynamicFee), 0);
    }

    function test_fuzz_getInitialSwapFee(uint24 fee) public {
        if (fee >> 23 == 1) {
            assertEq(SwapFeeLibrary.getInitialSwapFee(fee), 0);
        } else if (fee > 1000000) {
            vm.expectRevert(SwapFeeLibrary.FeeTooLarge.selector);
            SwapFeeLibrary.getInitialSwapFee(fee);
        } else {
            assertEq(SwapFeeLibrary.getInitialSwapFee(fee), fee);
        }
    }
}
