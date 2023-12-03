// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Currency, CurrencyLibrary} from "./types/Currency.sol";
import {IClaims} from "./interfaces/IClaims.sol";

/// An intentionally barebones balance mapping only supporting mint/burn/transfer
contract Claims is IClaims {
    using CurrencyLibrary for Currency;

    // Mapping from Currency to account balances
    mapping(Currency currency => mapping(address account => uint256)) private balances;

    /// @inheritdoc IClaims
    function balanceOf(address account, Currency currency) public view returns (uint256) {
        return balances[currency][account];
    }

    /// @inheritdoc IClaims
    function transfer(address to, Currency currency, uint256 amount) public {
        if (to == address(this)) revert InvalidAddress();

        if (amount > balances[currency][msg.sender]) revert InsufficientBalance();
        unchecked {
            balances[currency][msg.sender] -= amount;
        }
        balances[currency][to] += amount;
        emit Transfer(msg.sender, to, currency, amount);
    }

    /// @notice Mint `amount` of currency to address
    /// @param to The address to mint to
    /// @param currency The currency to mint
    /// @param amount The amount to mint
    function _mint(address to, Currency currency, uint256 amount) internal {
        balances[currency][to] += amount;
        emit Mint(to, currency, amount);
    }

    /// @notice Burn `amount` of currency from msg.sender
    /// @param currency The currency to mint
    /// @param amount The amount to burn
    /// @dev Will revert if the sender does not have enough balance
    function _burn(Currency currency, uint256 amount) internal {
        if (amount > balances[currency][msg.sender]) revert InsufficientBalance();
        unchecked {
            balances[currency][msg.sender] -= amount;
        }
        emit Burn(msg.sender, currency, amount);
    }
}
