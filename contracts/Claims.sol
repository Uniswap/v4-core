// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Currency, CurrencyLibrary} from "./types/Currency.sol";
import {IClaims} from "./interfaces/IClaims.sol";

/// An intentionally barebones balance mapping only supporting mint/burn/transfer
contract Claims is IClaims {
    using CurrencyLibrary for Currency;

    // Mapping from Currency id to account balances
    mapping(uint256 => mapping(address => uint256)) public balances;

    /// @inheritdoc IClaims
    function balanceOf(address account, Currency currency) public view returns (uint256) {
        return balances[currency.toId()][account];
    }

    /// @inheritdoc IClaims
    function transfer(address to, Currency currency, uint256 amount) public {
        if (to == address(0) || to == address(this)) revert InvalidAddress();

        uint256 id = currency.toId();
        if (amount > balances[id][msg.sender]) revert InsufficientBalance();
        unchecked {
            balances[id][msg.sender] -= amount;
        }
        balances[id][to] += amount;
        emit Transfer(msg.sender, to, id, amount);
    }

    /// @notice Mint `amount` of currency `id` to `to`
    /// @param to The address to mint to
    /// @param id The id to mint
    /// @param amount The amount to mint
    function _mint(address to, uint256 id, uint256 amount) internal {
        balances[id][to] += amount;
        emit Mint(to, id, amount);
    }

    /// @notice Burn `amount` of currency `id` from `msg.sender`
    /// @param id The id of the currency to burn
    /// @param amount The amount to burn
    /// @dev Will revert if the sender does not have enough balance
    function _burn(uint256 id, uint256 amount) internal {
        if (amount > balances[id][msg.sender]) revert InsufficientBalance();
        unchecked {
            balances[id][msg.sender] -= amount;
        }
        emit Burn(msg.sender, id, amount);
    }
}
