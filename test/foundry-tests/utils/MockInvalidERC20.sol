// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract MockInvalidERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals, uint256 amountToMint)
        ERC20(name, symbol, decimals)
    {
        mint(msg.sender, amountToMint);
    }

    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }

    function forceApprove(address _from, address _to, uint256 _amount) public returns (bool) {
        allowance[_from][_to] = _amount;

        emit Approval(_from, _to, _amount);

        return true;
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        uint256 balanceBefore = balanceOf[msg.sender];
        require(balanceBefore >= amount, "insufficient balance");
        balanceOf[msg.sender] = balanceBefore - amount;

        uint256 balanceRecipient = balanceOf[recipient];
        require(balanceRecipient + amount >= balanceRecipient, "recipient balance overflow");
        balanceOf[recipient] = balanceRecipient + amount;

        emit Transfer(msg.sender, recipient, amount);
        return false;
    }
}
