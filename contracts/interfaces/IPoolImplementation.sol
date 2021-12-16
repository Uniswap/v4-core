// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.2;

import {IPoolManager} from './IPoolManager.sol';
import {BalanceDelta} from './shared.sol';

interface IPoolImplementation {
    /// @notice Returns the address of the manager
    function manager() external view returns (IPoolManager);

    /// @notice Modifies a position with the given struct
    function modifyPosition(
        address sender,
        IPoolManager.Pair memory pair,
        bytes memory data
    ) external returns (BalanceDelta memory);

    /// @notice Execute a swap against the pool
    function swap(
        address sender,
        IPoolManager.Pair memory pair,
        bytes memory data
    ) external returns (BalanceDelta memory);
}
