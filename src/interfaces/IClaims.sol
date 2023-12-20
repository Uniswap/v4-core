// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Currency} from "../types/Currency.sol";

interface IClaims {
    /// @notice Thrown when user has insufficient Claims balance
    error InsufficientBalance();

    /// @notice Thrown when transferring Claims to this address
    error InvalidAddress();

    /// @notice Get the balance of `account` for `currency`
    /// @param account The account to get the balance of
    /// @param currency The currency to get the balance of
    function balanceOf(address account, Currency currency) external returns (uint256);

    /// @notice Transfer `amount` of `currency` from sender to `to`
    /// @param to The address to transfer to
    /// @param currency The currency to transfer
    /// @param amount The amount to transfer
    /// @dev Will revert if the sender does not have enough balance
    function transfer(address to, Currency currency, uint256 amount) external;

    /// @notice Emitted when minting `amount` of currency Claims to address
    event Mint(address indexed to, Currency indexed currency, uint256 amount);
    /// @notice Emitted when burning `amount` of currency Claims from address
    event Burn(address indexed from, Currency indexed currency, uint256 amount);
    /// @notice Emitted when transferring `amount` of currency Claims
    event Transfer(address indexed from, address indexed to, Currency indexed currency, uint256 amount);
}
