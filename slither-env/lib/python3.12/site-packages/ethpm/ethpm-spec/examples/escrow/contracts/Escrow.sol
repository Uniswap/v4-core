// SPDX-License-Identifier: MIT
pragma solidity ^0.6.8;


import {SafeSendLib} from "./SafeSendLib.sol";


/// @title Contract for holding funds in escrow between two semi trusted parties.
/// @author Piper Merriam <pipermerriam@gmail.com>
contract Escrow {
    using SafeSendLib for address;

    address public sender;
    address public recipient;

    constructor(address _recipient) public {
        sender = msg.sender;
        recipient = _recipient;
    }

    /// @dev Releases the escrowed funds to the other party.
    /// @notice This will release the escrowed funds to the other party.
    function releaseFunds() public {
        if (msg.sender == sender) {
            recipient.sendOrThrow(address(this).balance);
        } else if (msg.sender == recipient) {
            sender.sendOrThrow(address(this).balance);
        } else {
            revert();
        }
    }
}
