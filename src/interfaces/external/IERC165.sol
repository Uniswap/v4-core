// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IERC165 {
    /// @notice Checks if a contract implements an interface.
    /// @param interfaceId The interface identifier, as specified in ERC-165.
    /// @return supported True if the contract implements `interfaceId` and
    /// `interfaceId` is not 0xffffffff, false otherwise.
    function supportsInterface(bytes4 interfaceId) external view returns (bool supported);
}