// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

contract Owned {
    address public owner;

    /// @notice Emitted when the owner of the factory is changed
    /// @param oldOwner The owner before the owner was changed
    /// @param newOwner The owner after the owner was changed
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner);
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
