// SPDX-License-Identifier: GPL-2.0-or-later
import {IPoolManager} from '../IPoolManager.sol';
import {Pool} from '../../libraries/Pool.sol';

interface IHooks {
    struct Params {
        bool beforeModifyPosition;
        bool afterModifyPosition;
        bool beforeSwap;
        bool afterSwap;
        bool beforeTickCrossing;
        bool afterTickCrossing;
    }

    function beforeModifyPosition(
        address account,
        IPoolManager.PoolKey memory key,
        IPoolManager.ModifyPositionParams memory params
    ) external;

    function afterModifyPosition(
        address account,
        IPoolManager.PoolKey memory key,
        IPoolManager.ModifyPositionParams memory params
    ) external;

    function beforeSwap(
        address account,
        IPoolManager.PoolKey memory key,
        IPoolManager.SwapParams memory params
    ) external;

    function afterSwap(
        address account,
        IPoolManager.PoolKey memory key,
        IPoolManager.SwapParams memory params
    ) external;

    function beforeTickCrossing(
        address account,
        Pool.SwapParams memory params,
        Pool.SwapState memory swapState,
        Pool.StepComputations memory stepComputations
    ) external;

    function afterTickCrossing(
        address account,
        Pool.SwapParams memory params,
        Pool.SwapState memory swapState,
        Pool.StepComputations memory stepComputations
    ) external;
}
