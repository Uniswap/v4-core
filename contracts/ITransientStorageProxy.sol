// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.2;

interface ITransientStorageProxy {
    /// @dev Load the given slot from transient storage
    function load(bytes32 slot) external view returns (bytes32);

    /// @dev Store the value in the given slot to transient storage
    function store(bytes32 slot, bytes32 value) external;
}
