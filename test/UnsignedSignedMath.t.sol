// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {UnsignedSignedMath} from "../src/libraries/UnsignedSignedMath.sol";
import {Numbers} from "./utils/Numbers.sol";
import {stdError} from "forge-std/StdError.sol";
import {console2 as console} from "forge-std/console2.sol";

contract UnsignedSignedMathTest is Test, Numbers {
    using UnsignedSignedMath for uint128;

    function test_addOverflow() public {
        vm.expectRevert(stdError.arithmeticError);
        (type(uint128).max).add(1);
    }

    function test_addUnderflow() public {
        vm.expectRevert(stdError.arithmeticError);
        (type(uint128).min).add(-1);
    }

    function test_subOverflow() public {
        vm.expectRevert(stdError.arithmeticError);
        (type(uint128).min).sub(1);
    }

    function test_subUnderflow() public {
        vm.expectRevert(stdError.arithmeticError);
        (type(uint128).max).sub(-1);
    }
    /**
     * 25% => 1.8^2        => 3.24
     *     50% => 1.8 * 0.5    => 0.9      => 1.3225
     *     25% => 0.5^2        => 0.25
     */

    function test_validAdd(uint128 x, int128 y) public {
        int256 xAsSigned256 = int256(uint256(x));
        sanityCheck(xAsSigned256 >= 0);

        int256 maxDecrease = -xAsSigned256;
        int256 maxIncrease = int256(uint256(type(uint128).max)) - xAsSigned256;

        int256 boundY256 = bound(y, clampToI128(maxDecrease), clampToI128(maxIncrease));
        sanityCheck(boundY256 >= int256(type(int128).min) && boundY256 <= int256(type(int128).max));

        y = int128(boundY256);

        uint128 out = uint128(x.add(y));

        if (y < 0) {
            assertEq(uint256(x) - uint256(-int256(y)), out);
        } else {
            assertEq(uint256(x) + uint256(uint128(y)), out);
        }
    }

    function test_validSub(uint128 x, int128 y) public {
        int256 xAsSigned256 = int256(uint256(x));
        sanityCheck(xAsSigned256 >= 0);

        int256 maxDecrease = xAsSigned256;
        // Difference between x and max (but negated because it's a subtraction).
        int256 maxIncrease = -(int256(uint256(type(uint128).max)) - xAsSigned256);

        int256 boundY256 = bound(y, clampToI128(maxIncrease), clampToI128(maxDecrease));
        sanityCheck(boundY256 >= int256(type(int128).min) && boundY256 <= int256(type(int128).max));

        y = int128(boundY256);

        uint128 out = uint128(x.sub(y));

        if (y < 0) {
            assertEq(uint256(x) + uint256(-int256(y)), out);
        } else {
            assertEq(uint256(x) - uint256(uint128(y)), out);
        }
    }
}
