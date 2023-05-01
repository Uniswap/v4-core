// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals) ERC20(name, symbol, decimals) {}

    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }

    function forceApprove(address _from, address _to, uint256 _amount) public returns (bool) {
        allowance[_from][_to] = _amount;

        emit Approval(_from, _to, _amount);

        return true;
    }
}
