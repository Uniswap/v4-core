// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import {IExttload} from "./interfaces/IExttload.sol";
import {Extsload} from "./Extsload.sol";

/// @notice Enables public transient storage access for efficient state retrieval by external contracts.
/// https://eips.ethereum.org/EIPS/eip-2330#rationale
abstract contract Exttload is IExttload, Extsload {
    function exttload(bytes32 slot) external view returns (bytes32 value) {
        /// @solidity memory-safe-assembly
        assembly {
            value := tload(slot)
        }
    }
}
