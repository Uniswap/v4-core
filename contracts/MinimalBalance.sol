// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Currency, CurrencyLibrary} from "./types/Currency.sol";
import {IMinimalBalance} from "./interfaces/IMinimalBalance.sol";

contract MinimalBalance is IMinimalBalance {
    using CurrencyLibrary for Currency;
    // Mapping from Currency id to account balances
    mapping(uint256 => mapping(address => uint256)) private _balances;

     /// @inheritdoc IMinimalBalance
    function balanceOf(address account, Currency currency) external view returns (uint256) {
        // No check for zero address
        return _balances[currency.toId()][account];
    }
 
    /**
        @notice Mint `amount` of `id` and send it to `to`
        @param to The address to send the minted tokens to
        @param id The id of the token to mint
        @param amount The amount to mint
    */
    function _mint(
        address to,
        uint256 id,
        uint256 amount
    ) internal {
        _balances[id][to] += amount;
    }

    /**
        @notice Burn `amount` of `id` from `msg.sender`
        @param id The id of the token to burn
        @param amount The amount to burn
    */
    function _burn(
        uint256 id,
        uint256 amount
    ) internal {
        uint256 balance = _balances[id][msg.sender];
        if(balance < amount) revert InsufficientBalance();
        unchecked {
            _balances[id][msg.sender] = balance - amount;
        }
    }
}