// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.2;

import {IPoolManager} from './IPoolManager.sol';

interface IPoolImplementation {
    /// @notice Returns the address of the manager
    function manager() external view returns (IPoolManager);

    /// @notice Represents a change in the pool's balance of token0 and token1.
    struct BalanceDelta {
        int256 amount0;
        int256 amount1;
    }

    struct ModifyPositionParams {
        address owner;
        int256 liquidityDelta;
        bytes extraData;
    }

    /// @notice Modifies a position with the given struct
    function modifyPosition(ModifyPositionParams memory params) external returns (BalanceDelta memory);

    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice
    function swap(SwapParams memory params) external returns (BalanceDelta memory);
}
