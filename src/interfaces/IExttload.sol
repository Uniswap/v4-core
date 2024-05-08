// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

import {IExtsload} from "./IExtsload.sol";

interface IExttload is IExtsload {
    /// @notice Called by external contracts to access granular pool state
    /// @param slot Key of slot to sload
    /// @return value The value of the slot as bytes32
    function exttload(bytes32 slot) external view returns (bytes32 value);
}
