// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import {ERC6909} from "solmate/tokens/ERC6909.sol";

contract V46909 is ERC6909 {
    /// @notice Burn `amount` tokens of token type `id` from `from`.
    /// @param from The address to burn tokens from.
    /// @param id The currency to burn.
    /// @param amount The amount to burn.
    function _burnFrom(address from, uint256 id, uint256 amount) internal {
        address sender = msg.sender;
        if (from != sender && !isOperator[from][sender]) {
            uint256 senderAllowance = allowance[from][sender][id];
            if (senderAllowance != type(uint256).max) {
                allowance[from][sender][id] = senderAllowance - amount;
            }
        }
        _burn(from, id, amount);
    }
}
