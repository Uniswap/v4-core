// SPDX-License-Identifier: MIT
pragma solidity ^0.6.8;


import {SafeMathLib} from "./safe-math-lib/contracts/SafeMathLib.sol";
import {Owned} from "./owned/contracts/Owned.sol";


/// @title Contract for holding funds in escrow between two semi trusted parties.
/// @author Piper Merriam <pipermerriam@gmail.com>
contract Wallet is Owned {
    using SafeMathLib for uint;

    mapping (address => uint) allowances;

    /// @dev Fallback function for depositing funds
    fallback() external {
    }

    /// @dev Sends the recipient the specified amount
    /// @notice This will send the reciepient the specified amount.
    function send(address payable recipient, uint value) public onlyOwner returns (bool) {
        return recipient.send(value);
    }

    /// @dev Sets recipient to be approved to withdraw the specified amount
    /// @notice This will set the recipient to be approved to withdraw the specified amount.
    function approve(address recipient, uint value) public onlyOwner returns (bool) {
        allowances[recipient] = value;
        return true;
    }

    /// @dev Lets caller withdraw up to their approved amount
    /// @notice This will withdraw provided value, deducting it from your total allowance.
    function withdraw(uint value) public returns (bool) {
        allowances[msg.sender] = allowances[msg.sender].safeSub(value);
        if (!msg.sender.send(value))
            revert();
        return true;
    }
}
