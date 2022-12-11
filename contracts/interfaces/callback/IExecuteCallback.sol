// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.2;

import {CurrencyDelta} from '../../libraries/CurrencyDelta.sol';

interface IExecuteCallback {
    /// @notice Called by the pool manager on `msg.sender` when a lock is acquired
    /// @param data The data that was passed to the call to lock
    /// @return Any data that you want to be returned from the lock call
    function executeCallback(CurrencyDelta[] memory deltas, bytes calldata data) external returns (bytes memory);
}
