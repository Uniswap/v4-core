// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.2;

import {IPoolManager} from '../IPoolManager.sol';
import {Pool} from '../../libraries/Pool.sol';

/// @notice V4 decides whether to invoke specific hooks by inspecting the leading bits of the address that
/// @notice the hooks contract is deployed to. For example, a 1 bit in the first bit of the address will
/// @notice cause the 'before swap' hook to be invoked. See the Hooks library for the full spec.
interface IHooks {
    struct Params {
        bool beforeModifyPosition;
        bool afterModifyPosition;
        bool beforeSwap;
        bool afterSwap;
    }

    function beforeModifyPosition(
        address sender,
        IPoolManager.PoolKey memory key,
        IPoolManager.ModifyPositionParams memory params
    ) external;

    function afterModifyPosition(
        address sender,
        IPoolManager.PoolKey memory key,
        IPoolManager.ModifyPositionParams memory params
    ) external;

    function beforeSwap(
        address sender,
        IPoolManager.PoolKey memory key,
        IPoolManager.SwapParams memory params
    ) external;

    function afterSwap(
        address sender,
        IPoolManager.PoolKey memory key,
        IPoolManager.SwapParams memory params,
        Pool.BalanceDelta memory delta
    ) external;
}
