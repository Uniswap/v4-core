// SPDX-License-Identifier: MIT
pragma solidity ^0.6.8;


/// @title Library for safe sending of ether.
/// @author Piper Merriam <pipermerriam@gmail.com>
library SafeSendLib {
    /// @dev Attempts to send the specified amount to the recipient throwing an error if it fails
    /// @param recipient The address that the funds should be to.
    /// @param value The amount in wei that should be sent.
    function sendOrThrow(address recipient, uint value) public returns (bool) {
        if (value > address(this).balance)
            revert();

        if (!payable(recipient).send(value))
            revert();

        return true;
    }
}
