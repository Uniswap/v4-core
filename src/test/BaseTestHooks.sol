// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IHooks} from "../interfaces/IHooks.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {ModifyLiquidityParams, SwapParams} from "../types/PoolOperation.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {BeforeSwapDelta} from "../types/BeforeSwapDelta.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";

contract BaseTestHooks is IHooks {
    error HookNotImplemented();

    function beforeInitialize(address, /* sender **/ PoolKey calldata, /* key **/ uint160 /* sqrtPriceX96 **/ )
        external
        virtual
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterInitialize(
        address, /* sender **/
        PoolKey calldata, /* key **/
        uint160, /* sqrtPriceX96 **/
        int24 /* tick **/
    ) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function beforeAddLiquidity(
        address, /* sender **/
        PoolKey calldata, /* key **/
        ModifyLiquidityParams calldata, /* params **/
        bytes calldata /* hookData **/
    ) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterAddLiquidity(
        address, /* sender **/
        PoolKey calldata, /* key **/
        ModifyLiquidityParams calldata, /* params **/
        BalanceDelta, /* delta **/
        BalanceDelta, /* feeDelta **/
        bytes calldata /* hookData **/
    ) external virtual returns (bytes4, BalanceDelta) {
        revert HookNotImplemented();
    }

    function beforeRemoveLiquidity(
        address, /* sender **/
        PoolKey calldata, /* key **/
        ModifyLiquidityParams calldata, /* params **/
        bytes calldata /* hookData **/
    ) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterRemoveLiquidity(
        address, /* sender **/
        PoolKey calldata, /* key **/
        ModifyLiquidityParams calldata, /* params **/
        BalanceDelta, /* delta **/
        BalanceDelta, /* feeDelta **/
        bytes calldata /* hookData **/
    ) external virtual returns (bytes4, BalanceDelta) {
        revert HookNotImplemented();
    }

    function beforeSwap(
        address, /* sender **/
        PoolKey calldata, /* key **/
        SwapParams calldata, /* params **/
        bytes calldata /* hookData **/
    ) external virtual returns (bytes4, BeforeSwapDelta, uint24) {
        revert HookNotImplemented();
    }

    function afterSwap(
        address, /* sender **/
        PoolKey calldata, /* key **/
        SwapParams calldata, /* params **/
        BalanceDelta, /* delta **/
        bytes calldata /* hookData **/
    ) external virtual returns (bytes4, int128) {
        revert HookNotImplemented();
    }

    function beforeDonate(
        address, /* sender **/
        PoolKey calldata, /* key **/
        uint256, /* amount0 **/
        uint256, /* amount1 **/
        bytes calldata /* hookData **/
    ) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterDonate(
        address, /* sender **/
        PoolKey calldata, /* key **/
        uint256, /* amount0 **/
        uint256, /* amount1 **/
        bytes calldata /* hookData **/
    ) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }
}
