// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

contract Owned {
    address public owner;
    bytes12 private STORAGE_PLACEHOLDER;

    error InvalidCaller();

    /// @notice Emitted when the owner of the factory is changed
    /// @param oldOwner The owner before the owner was changed
    /// @param newOwner The owner after the owner was changed
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    modifier onlyOwner() {
        if (msg.sender != owner) revert InvalidCaller();
        _;
    }

    constructor() {
        owner = msg.sender;
        emit OwnerChanged(address(0), msg.sender);
    }

    function setOwner(address _owner) external onlyOwner {
        emit OwnerChanged(owner, _owner);
        owner = _owner;
    }
}
