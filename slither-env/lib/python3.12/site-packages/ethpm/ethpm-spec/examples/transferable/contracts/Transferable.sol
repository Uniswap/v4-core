// SPDX-License-Identifier: MIT
pragma solidity ^0.6.8;

import {Owned} from "owned/contracts/Owned.sol";

contract Transferable is Owned {
    event OwnerChanged(address indexed prevOwner, address indexed newOwner);

    function transferOwner(address newOwner) public onlyOwner returns (bool) {
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
        return true;
    }
}
