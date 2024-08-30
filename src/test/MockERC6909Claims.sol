// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC6909Claims} from "../ERC6909Claims.sol";

/// @notice Mock contract for testing ERC6909Claims
contract MockERC6909Claims is ERC6909Claims {
    /// @notice mocked mint logic
    function mint(address to, uint256 id, uint256 amount) public {
        _mint(to, id, amount);
    }

    /// @notice mocked burn logic
    function burn(uint256 id, uint256 amount) public {
        _burn(msg.sender, id, amount);
    }

    /// @notice mocked burn logic without checking sender allowance
    function burnFrom(address from, uint256 id, uint256 amount) public {
        _burnFrom(from, id, amount);
    }
}
