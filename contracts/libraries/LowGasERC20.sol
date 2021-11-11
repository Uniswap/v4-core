// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20Minimal} from '../interfaces/external/IERC20Minimal.sol';

/// @notice Helper functions for more cheaply interacting with ERC20 contracts
library LowGasERC20 {
    /// @dev Get the balance of a token with minimum gas
    /// @dev This function is gas optimized to avoid a redundant extcodesize check in addition to the returndatasize
    /// check
    function balance(address token) internal view returns (uint256) {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, address(this))
        );
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }
}
