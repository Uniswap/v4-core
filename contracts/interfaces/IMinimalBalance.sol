// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Currency} from "../types/Currency.sol";

interface IMinimalBalance {
    error InvalidAddress();
    error InsufficientBalance();

    /// @notice Called by the user get their balance
    function balanceOf(address account, Currency currency) external returns (uint256);

    event Mint(address indexed to, uint256 indexed id, uint256 amount);
    event Burn(address indexed from, uint256 indexed id, uint256 amount);
}
