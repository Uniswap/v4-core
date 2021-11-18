// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IPayCallback {
    struct TokenAmountOwed {
        address token;
        uint256 amount;
    }

    /// @notice Called on the `msg.sender` after a lock is released
    function payCallback(TokenAmountOwed[] calldata amountOwed) external;
}
