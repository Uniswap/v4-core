// SPDX-License-Identifier: MIT
pragma solidity ^0.6.8;


/// Implements ERC 20 Token standard: https://github.com/ethereum/EIPs/issues/20

/// @title Abstract token contract - Functions to be implemented by token contracts.
/// @author Stefan George - <stefan.george@consensys.net>
abstract contract Token {
    // This is not an abstract function, because solc won't recognize generated getter functions for public variables as functions
    function totalSupply() external view virtual returns (uint256 supply) {}
    function balanceOf(address owner) public view virtual returns (uint256 balance);
    function transfer(address to, uint256 value) public virtual returns (bool success);
    function transferFrom(address from, address to, uint256 value) public virtual returns (bool success);
    function approve(address spender, uint256 value) public virtual returns (bool success);
    function allowance(address owner, address spender) public view virtual returns (uint256 remaining);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}
