// SPDX-License-Identifier: MIT
pragma solidity ^0.6.8;


/// @title Safe Math Library
/// @author Piper Merriam <pipermerriam@gmail.com>
library SafeMathLib {
    /// @dev Adds a and b, throwing an error if the operation would cause an overflow.
    /// @param a The first number to add
    /// @param b The second number to add
    function safeAdd(uint256 a, uint256 b) public pure returns (uint256 c) {
        c = a + b;
        assert(c >= a);
        return c;
    }

    /// @dev Subtracts b from a, throwing an error if the operation would cause an underflow.
    /// @param a The number to be subtracted from
    /// @param b The amount that should be subtracted
    function safeSub(uint256 a, uint256 b) public pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }
}
