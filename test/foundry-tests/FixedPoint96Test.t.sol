// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {FixedPoint96, UQ64x96} from "../../contracts/libraries/FixedPoint96.sol";
import {FullMath} from "../../contracts/libraries/FullMath.sol";
import {SafeCast} from "../../contracts/libraries/SafeCast.sol";

contract FixedPoint96Test is Test {
    using SafeCast for uint256;

    function testNoOverflowUncheckedAdd(UQ64x96 a, UQ64x96 b) public {
        // assume no overflow
        vm.assume(a.toUint256() + b.toUint256() < 2 ** 160);
        UQ64x96 result = a + b;
        assertEq(UQ64x96.unwrap(result), UQ64x96.unwrap(FixedPoint96.uncheckedAdd(a, b)));
    }

    function testNoOverflowUncheckedSub(UQ64x96 a, UQ64x96 b) public {
        // assume no overflow
        vm.assume(a.toUint256() > b.toUint256() && a.toUint256() - b.toUint256() < 2 ** 160);
        UQ64x96 result = a - b;
        assertEq(UQ64x96.unwrap(result), UQ64x96.unwrap(FixedPoint96.uncheckedSub(a, b)));
    }

    function testNoOverflowUncheckedMul(uint160 a, uint160 b) public {
        // these values are proper UQ64x96 values
        UQ64x96 _a = UQ64x96.wrap(((uint256(a) >> FixedPoint96.RESOLUTION) << FixedPoint96.RESOLUTION).toUint160());
        UQ64x96 _b = UQ64x96.wrap(((uint256(b) >> FixedPoint96.RESOLUTION) << FixedPoint96.RESOLUTION).toUint160());
        // assume no overflow
        uint256 overflowCheck = _a.toUint256();
        if (_b != UQ64x96.wrap(0)) {
            unchecked {
                overflowCheck = _a.toUint256() * _b.toUint256() / _b.toUint256();
            }
        }
        vm.assume(overflowCheck == _a.toUint256());
        uint256 result = _a.toUint256() * _b.toUint256() / 2 ** 96;
        assertEq(result, UQ64x96.unwrap(FixedPoint96.uncheckedMul(_a, _b)));
    }

    function testIntermediateOverflowUncheckedMul(uint160 a, uint160 b) public {
        // these values are proper UQ64x96 values
        UQ64x96 _a = UQ64x96.wrap(((uint256(a) >> FixedPoint96.RESOLUTION) << FixedPoint96.RESOLUTION).toUint160());
        UQ64x96 _b = UQ64x96.wrap(((uint256(b) >> FixedPoint96.RESOLUTION) << FixedPoint96.RESOLUTION).toUint160());

        uint256 result = FullMath.mulDiv(_a.toUint256(), _b.toUint256(), 2 ** 96);
        vm.assume(result < 2 ** 160);
        assertEq(result, UQ64x96.unwrap(FixedPoint96.uncheckedMul(_a, _b)));
    }

    function testNoOverflowUncheckedDiv(uint160 a, uint160 b) public {
        // these values are proper UQ64x96 values
        UQ64x96 _a = UQ64x96.wrap(((uint256(a) >> FixedPoint96.RESOLUTION) << FixedPoint96.RESOLUTION).toUint160());
        UQ64x96 _b = UQ64x96.wrap(((uint256(b) >> FixedPoint96.RESOLUTION) << FixedPoint96.RESOLUTION).toUint160());

        vm.assume(_b != UQ64x96.wrap(0));

        // assume no overflow
        uint256 overflowCheck = _a.toUint256();
        unchecked {
            overflowCheck = _a.toUint256() * 2 ** 96 / 2 ** 96;
        }
        vm.assume(overflowCheck == _a.toUint256());
        uint256 result = _a.toUint256() * 2 ** 96 / _b.toUint256();
        assertEq(result, UQ64x96.unwrap(FixedPoint96.uncheckedDiv(_a, _b)));
    }

    function testIntermediateOverflowUncheckedDiv(uint160 a, uint160 b) public {
        // these values are proper UQ64x96 values
        UQ64x96 _a = UQ64x96.wrap(((uint256(a) >> FixedPoint96.RESOLUTION) << FixedPoint96.RESOLUTION).toUint160());
        UQ64x96 _b = UQ64x96.wrap(((uint256(b) >> FixedPoint96.RESOLUTION) << FixedPoint96.RESOLUTION).toUint160());

        vm.assume(_b != UQ64x96.wrap(0));

        uint256 result = FullMath.mulDiv(_a.toUint256(), 2 ** 96, _b.toUint256());
        vm.assume(result < 2 ** 160);
        assertEq(result, UQ64x96.unwrap(FixedPoint96.uncheckedDiv(_a, _b)));
    }
}
