// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {FixedPoint128, UQ128x128} from "../../contracts/libraries/FixedPoint128.sol";
import {FullMath} from "../../contracts/libraries/FullMath.sol";

contract FixedPoint128Test is Test {
    function testOverflowCheckedAdd(UQ128x128 a, UQ128x128 b) public {
        vm.assume(a != b);
        uint256 overflowCheck;
        unchecked {
            overflowCheck = a.toUint256() + b.toUint256();
        }
        if (a > b) {
            vm.assume(a.toUint256() > overflowCheck);
            vm.expectRevert();
            UQ128x128 result = a + b;
        } else {
            // b > a
            vm.assume(b.toUint256() > overflowCheck);
            vm.expectRevert();
            UQ128x128 result = a + b;
        }
    }

    function testNoOverflowUncheckedAdd(UQ128x128 a, UQ128x128 b) public {
        vm.assume(a != b);
        uint256 overflowCheck;
        unchecked {
            overflowCheck = a.toUint256() + b.toUint256();
        }
        if (a > b) {
            vm.assume(a.toUint256() <= overflowCheck);
            UQ128x128 result = a + b;
            assertEq(result.toUint256(), FixedPoint128.uncheckedAdd(a, b).toUint256());
        } else {
            // b > a
            vm.assume(b.toUint256() <= overflowCheck);
            UQ128x128 result = a + b;
            assertEq(result.toUint256(), FixedPoint128.uncheckedAdd(a, b).toUint256());
        }
    }

    function testNoOverflowUncheckedSub(UQ128x128 a, UQ128x128 b) public {
        // assume no overflow
        vm.assume(a.toUint256() > b.toUint256() && a.toUint256() - b.toUint256() < type(uint256).max);
        UQ128x128 result = a - b;
        assertEq(UQ128x128.unwrap(result), UQ128x128.unwrap(FixedPoint128.uncheckedSub(a, b)));
    }

    function testNoOverflowUncheckedMul(uint256 a, uint256 b) public {
        // these values are proper UQ128x128 values
        UQ128x128 _a = UQ128x128.wrap(a);
        UQ128x128 _b = UQ128x128.wrap(a);
        // assume no overflow
        uint256 overflowCheck = _a.toUint256();
        if (_b != UQ128x128.wrap(0)) {
            unchecked {
                overflowCheck = _a.toUint256() * _b.toUint256() / _b.toUint256();
            }
        }
        vm.assume(overflowCheck == _a.toUint256());
        uint256 result = _a.toUint256() * _b.toUint256() / 2 ** 128;
        assertEq(result, UQ128x128.unwrap(FixedPoint128.uncheckedMul(_a, _b)));
    }

    function testIntermediateOverflowUncheckedMul(uint256 a, uint256 b) public {
        // these values are proper UQ128x128 values
        UQ128x128 _a = UQ128x128.wrap(a);
        UQ128x128 _b = UQ128x128.wrap(b);

        uint256 result = FullMath.mulDiv(_a.toUint256(), _b.toUint256(), 2 ** 128);
        vm.assume(result < type(uint256).max);
        assertEq(result, UQ128x128.unwrap(FixedPoint128.uncheckedMul(_a, _b)));
    }

    function testNoOverflowUncheckedDiv(uint256 a, uint256 b) public {
        // these values are proper UQ128x128 values
        UQ128x128 _a = UQ128x128.wrap(a);
        UQ128x128 _b = UQ128x128.wrap(b);
        vm.assume(_b != UQ128x128.wrap(0));

        // assume no overflow
        uint256 overflowCheck = _a.toUint256();
        unchecked {
            overflowCheck = _a.toUint256() * 2 ** 128 / 2 ** 128;
        }
        vm.assume(overflowCheck == _a.toUint256());
        uint256 result = _a.toUint256() * 2 ** 128 / _b.toUint256();
        assertEq(result, UQ128x128.unwrap(FixedPoint128.uncheckedDiv(_a, _b)));
    }

    function testIntermediateOverflowUncheckedDiv(uint256 a, uint256 b) public {
        // these values are proper UQ128x128 values
        UQ128x128 _a = UQ128x128.wrap(a);
        UQ128x128 _b = UQ128x128.wrap(b);
        vm.assume(_b != UQ128x128.wrap(0));

        uint256 result = FullMath.mulDiv(UQ128x128.unwrap(_a), 2 ** 128, UQ128x128.unwrap(_b));
        vm.assume(result < type(uint256).max);
        assertEq(result, UQ128x128.unwrap(FixedPoint128.uncheckedDiv(_a, _b)));
    }
}
