pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {SafeCast} from "../../contracts/libraries/SafeCast.sol";

contract SafeCastTest is Test {
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

    function testToInt128(uint256 x) public {
        if (x <= uint128(type(int128).max)) {
            assertEq(uint128(SafeCast.toInt128(x)), x);
        } else {
            vm.expectRevert();
            SafeCast.toInt128(x);
        }
    }
}
