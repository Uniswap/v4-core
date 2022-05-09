pragma solidity ^0.8.13;

import {DSTest} from '../../foundry/testdata/lib/ds-test/src/test.sol';
import {Cheats} from '../../foundry/testdata/cheats/Cheats.sol';
import {SafeCast} from '../libraries/SafeCast.sol';

contract SafeCastTest is DSTest {
    Cheats vm = Cheats(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function testToUint160(uint256 x) public {
        if (x <= type(uint160).max) {
            assertEq(uint256(SafeCast.toUint160(x)), x);
        } else {
            vm.expectRevert();
            SafeCast.toUint160(x);
        }
    }

    function testToInt128(int256 x) public {
        if (x <= type(int128).max && x >= type(int128).min) {
            assertEq(int256(SafeCast.toInt128(x)), x);
        } else {
            vm.expectRevert();
            SafeCast.toInt128(x);
        }
    }

    function testToInt256(uint256 x) public {
        if (x <= uint256(type(int256).max)) {
            assertEq(uint256(SafeCast.toInt256(x)), x);
        } else {
            vm.expectRevert();
            SafeCast.toInt256(x);
        }
    }

    function testToInt248(int256 x) public {
        if (x <= type(int248).max && x >= type(int248).min) {
            assertEq(int256(SafeCast.toInt248(x)), x);
        } else {
            vm.expectRevert();
            SafeCast.toInt248(x);
        }
    }
}
