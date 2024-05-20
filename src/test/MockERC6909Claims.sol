// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC6909Claims} from "../ERC6909Claims.sol";
import {CurrencyLibrary, Currency} from "../types/Currency.sol";

/// @notice Mock contract for testing ERC6909Claims
contract MockERC6909Claims is ERC6909Claims {
    using CurrencyLibrary for Currency;

    /// @notice mocked balance slot salt
    function balanceSlotSalt() public pure returns (uint8 salt) {
        salt = BALANCES_SLOT_SALT;
    }

    /// @notice mocked allowance slot salt
    function allowanceSlotSalt() public pure returns (uint8 salt) {
        salt = ALLOWANCES_SLOT_SALT;
    }

    /// @notice mocked operator slot salt
    function operatorSlotSalt() public pure returns (uint8 salt) {
        salt = OPERATORS_SLOT_SALT;
    }

    /// @notice mocked operator storage slot derivation
    function getOperatorSlot(address owner, address spender) public pure returns (bytes32 slot) {
        slot = _getOperatorSlot(owner, spender);
    }

    /// @notice mocked allowance storage slot derivation
    function getAllowanceSlot(address owner, address spender, uint256 id) public pure returns (bytes32 slot) {
        slot = _getAllowanceSlot(owner, spender, id);
    }

    /// @notice mocked balance storage slot derivation
    function getBalanceSlot(address owner, uint256 id) public pure returns (bytes32 slot) {
        slot = _getBalanceSlot(owner, id);
    }

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
