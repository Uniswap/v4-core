// SPDX-License-Identifier: MIT
pragma solidity ^0.6.8;


import {Wallet} from "./wallet/contracts/Wallet.sol";


/// @title Wallet contract with simple send and approval spending functionality
/// @author Piper Merriam <pipermerriam@gmail.com>
contract WalletWithSend is Wallet {
    /// @dev Sends funds that have been approved to the specified address
    /// @notice This will send the reciepient the specified amount.
    function approvedSend(uint value, address payable to) public {
        allowances[msg.sender] = allowances[msg.sender].safeSub(value);
        if (!to.send(value))
            revert();
    }
}
