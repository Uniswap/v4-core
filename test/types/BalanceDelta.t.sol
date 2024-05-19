// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {BalanceDelta, toBalanceDelta} from "../../src/types/BalanceDelta.sol";

contract TestBalanceDelta is Test {

    /////////////////////////////////////////////////////
    /////////////////// toBalanceDelta //////////////////
    /////////////////////////////////////////////////////

    function test_toBalanceDelta() external pure {
        _test_toBalanceDelta(0, 0);
        _test_toBalanceDelta(0, 1);
        _test_toBalanceDelta(1, 0);
        _test_toBalanceDelta(type(int128).max, type(int128).max);
        _test_toBalanceDelta(type(int128).min, type(int128).min);
    }

    function test_fuzz_toBalanceDelta(int128 x, int128 y) external pure {
        _test_toBalanceDelta(x, y);
    }

    function test_fuzz_toBalanceDelta_unwrap(int128 x, int128 y) external pure {
        // Act
        BalanceDelta balanceDelta = toBalanceDelta(x, y);

        // Assert
        int256 expectedBD = int256(uint256(bytes32(abi.encodePacked(x, y))));
        assertEq(BalanceDelta.unwrap(balanceDelta), expectedBD);
    }

    function _test_toBalanceDelta(int128 _amount0, int128 _amount1) internal pure {
        // Act
        BalanceDelta balanceDelta = toBalanceDelta(_amount0, _amount1);

        // Assert
        assertEq(balanceDelta.amount0(), _amount0);
        assertEq(balanceDelta.amount1(), _amount1);
    }

    /////////////////////////////////////////////////////
    //////////////////////// add ////////////////////////
    /////////////////////////////////////////////////////

    function test_add() external pure {
        // parameters: left balance delta Amount0, Amount1, right balance delta Amount0, Amount1
        _test_add(0, 0, 0, 0);
        _test_add(-1000, 1000, 1000, -1000);
        _test_add(type(int128).min, type(int128).max, type(int128).max, type(int128).min);
        _test_add(type(int128).max / 2 + 1, type(int128).max / 2 + 1, type(int128).max / 2, type(int128).max / 2);
    }

    function test_add_revertsOnOverflow() external {
        // parameters: left balance delta Amount0, Amount1, right balance delta Amount0, Amount1
        _test_add_revertsOnOverflow(type(int128).max, 0, 1, 0);
        _test_add_revertsOnOverflow(0, type(int128).max, 0, 1);
        _test_add_revertsOnOverflow(type(int128).min, 0, -1, 0);
        _test_add_revertsOnOverflow(0, type(int128).min, 0, -1);
    }

    function test_fuzz_add(int128 _leftAmount0, int128 _leftAmount1, int128 _rightAmount0, int128 _rightAmount1) external {
        int256 sumOfAmount0 = int256(_leftAmount0) + _rightAmount0;
        int256 sumOfAmount1 = int256(_leftAmount1) + _rightAmount1;
        bool isOverflow = sumOfAmount0 != int128(sumOfAmount0) || sumOfAmount1 != int128(sumOfAmount1);

        if (isOverflow) {
            _test_add_revertsOnOverflow(_leftAmount0, _leftAmount1, _rightAmount0, _rightAmount1);
        } else {
            _test_add(_leftAmount0, _leftAmount1, _rightAmount0, _rightAmount1);
        }
    }

    function _test_add(int128 _leftAmount0, int128 _leftAmount1, int128 _rightAmount0, int128 _rightAmount1) internal pure {
        // Arrange
        BalanceDelta balanceDelta0 = toBalanceDelta(_leftAmount0, _leftAmount1);
        BalanceDelta balanceDelta1 = toBalanceDelta(_rightAmount0, _rightAmount1);

        // Act
        BalanceDelta sumBalanceDelta = balanceDelta0 + balanceDelta1;

        // Assert
        assertEq(sumBalanceDelta.amount0(), _leftAmount0 + _rightAmount0);
        assertEq(sumBalanceDelta.amount1(), _leftAmount1 + _rightAmount1);
    }

    function _test_add_revertsOnOverflow(int128 _leftAmount0, int128 _leftAmount1, int128 _rightAmount0, int128 _rightAmount1) internal {
        // Arrange
        BalanceDelta balanceDelta0 = toBalanceDelta(_leftAmount0, _leftAmount1);
        BalanceDelta balanceDelta1 = toBalanceDelta(_rightAmount0, _rightAmount1);

        // Act & Assert
        vm.expectRevert(bytes4(0x93dafdf1)); // Revert: SafeCastOverflow()
        balanceDelta0 + balanceDelta1;
    }

    /////////////////////////////////////////////////////
    //////////////////////// sub ////////////////////////
    /////////////////////////////////////////////////////

    function test_sub() external pure {
        _test_sub(0, 0, 0, 0);
        _test_sub(-1000, 1000, 1000, -1000);
        _test_sub(-1000, -1000, -(type(int128).min + 1000), -(type(int128).min + 1000));
        _test_sub(type(int128).min / 2, type(int128).min / 2, -(type(int128).min / 2), -(type(int128).min / 2));
    }

    function test_sub_revertsOnOverflow() external {
        // parameters: left balance delta Amount0, Amount1, right balance delta Amount0, Amount1
        _test_sub_revertsOnOverflow(type(int128).min, 0, 1, 0);
        _test_sub_revertsOnOverflow(0, type(int128).min, 0, 1);
        _test_sub_revertsOnOverflow(type(int128).max, 0, -1, 0);
        _test_sub_revertsOnOverflow(0, type(int128).max, 0, -1);
    }

    function test_fuzz_sub(int128 _leftAmount0, int128 _leftAmount1, int128 _rightAmount0, int128 _rightAmount1) external {
        int256 subOfAmount0 = int256(_leftAmount0) - _rightAmount0;
        int256 subOfAmount1 = int256(_leftAmount1) - _rightAmount1;
        bool isUnderflow = subOfAmount0 != int128(subOfAmount0) || subOfAmount1 != int128(subOfAmount1);

        if (isUnderflow) {
            _test_sub_revertsOnOverflow(_leftAmount0, _leftAmount1, _rightAmount0, _rightAmount1);
        } else {
            _test_sub(_leftAmount0, _leftAmount1, _rightAmount0, _rightAmount1);
        }
    }

    function _test_sub(int128 _leftAmount0, int128 _leftAmount1, int128 _rightAmount0, int128 _rightAmount1) internal pure {
        // Arrange
        BalanceDelta balanceDelta0 = toBalanceDelta(_leftAmount0, _leftAmount1);
        BalanceDelta balanceDelta1 = toBalanceDelta(_rightAmount0, _rightAmount1);

        // Act
        BalanceDelta subBalanceDelta = balanceDelta0 - balanceDelta1;

        // Assert
        assertEq(subBalanceDelta.amount0(), _leftAmount0 - _rightAmount0);
        assertEq(subBalanceDelta.amount1(), _leftAmount1 - _rightAmount1);
    }

    function _test_sub_revertsOnOverflow(int128 _leftAmount0, int128 _leftAmount1, int128 _rightAmount0, int128 _rightAmount1) internal {
        // Arrange
        BalanceDelta balanceDelta0 = toBalanceDelta(_leftAmount0, _leftAmount1);
        BalanceDelta balanceDelta1 = toBalanceDelta(_rightAmount0, _rightAmount1);

        // Act & Assert
        vm.expectRevert(bytes4(0x93dafdf1)); // Revert: SafeCastOverflow()
        balanceDelta0 - balanceDelta1;
    }

    /////////////////////////////////////////////////////
    ///////////////////////// eq ////////////////////////
    /////////////////////////////////////////////////////

    function test_fuzz_eq(int128 a, int128 b, int128 c, int128 d) public pure {
        // Act
        bool isEqual = (toBalanceDelta(a, b) == toBalanceDelta(c, d));

        // Assert
        assertEq(isEqual, a == c && b == d);
    }

    /////////////////////////////////////////////////////
    //////////////////////// neq ////////////////////////
    /////////////////////////////////////////////////////

    function test_fuzz_neq(int128 a, int128 b, int128 c, int128 d) public pure {
        // Act
        bool isNotEqual = (toBalanceDelta(a, b) != toBalanceDelta(c, d));

        // Assert
        assertEq(isNotEqual, a != c || b != d);
    }
}
