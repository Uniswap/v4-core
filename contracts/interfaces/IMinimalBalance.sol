// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Currency} from "../types/Currency.sol";

interface IMinimalBalance {
    error InsufficientBalance();

    /// @notice Called by the user get their balance of ERC1155
    function balanceOf(address account, Currency currency) external returns (uint256);
}