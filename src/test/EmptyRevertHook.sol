// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IHooks} from "../interfaces/IHooks.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDeltas} from "../types/BalanceDeltas.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {BeforeSwapDeltas} from "../types/BeforeSwapDeltas.sol";

contract EmptyRevertHook is IHooks {
    function beforeInitialize(
        address, /* sender **/
        PoolKey calldata, /* key **/
        uint160, /* sqrtPriceX96 **/
        bytes calldata /* hookData **/
    ) external virtual returns (bytes4) {
        revert();
    }

    function afterInitialize(
        address, /* sender **/
        PoolKey calldata, /* key **/
        uint160, /* sqrtPriceX96 **/
        int24, /* tick **/
        bytes calldata /* hookData **/
    ) external virtual returns (bytes4) {
        revert();
    }

    function beforeAddLiquidity(
        address, /* sender **/
        PoolKey calldata, /* key **/
        IPoolManager.ModifyLiquidityParams calldata, /* params **/
        bytes calldata /* hookData **/
    ) external virtual returns (bytes4) {
        revert();
    }

    function afterAddLiquidity(
        address, /* sender **/
        PoolKey calldata, /* key **/
        IPoolManager.ModifyLiquidityParams calldata, /* params **/
        BalanceDeltas, /* deltas **/
        bytes calldata /* hookData **/
    ) external virtual returns (bytes4, BalanceDeltas) {
        revert();
    }

    function beforeRemoveLiquidity(
        address, /* sender **/
        PoolKey calldata, /* key **/
        IPoolManager.ModifyLiquidityParams calldata, /* params **/
        bytes calldata /* hookData **/
    ) external virtual returns (bytes4) {
        revert();
    }

    function afterRemoveLiquidity(
        address, /* sender **/
        PoolKey calldata, /* key **/
        IPoolManager.ModifyLiquidityParams calldata, /* params **/
        BalanceDeltas, /* deltas **/
        bytes calldata /* hookData **/
    ) external virtual returns (bytes4, BalanceDeltas) {
        revert();
    }

    function beforeSwap(
        address, /* sender **/
        PoolKey calldata, /* key **/
        IPoolManager.SwapParams calldata, /* params **/
        bytes calldata /* hookData **/
    ) external virtual returns (bytes4, BeforeSwapDeltas, uint24) {
        revert();
    }

    function afterSwap(
        address, /* sender **/
        PoolKey calldata, /* key **/
        IPoolManager.SwapParams calldata, /* params **/
        BalanceDeltas, /* deltas **/
        bytes calldata /* hookData **/
    ) external virtual returns (bytes4, int128) {
        revert();
    }

    function beforeDonate(
        address, /* sender **/
        PoolKey calldata, /* key **/
        uint256, /* amount0 **/
        uint256, /* amount1 **/
        bytes calldata /* hookData **/
    ) external virtual returns (bytes4) {
        revert();
    }

    function afterDonate(
        address, /* sender **/
        PoolKey calldata, /* key **/
        uint256, /* amount0 **/
        uint256, /* amount1 **/
        bytes calldata /* hookData **/
    ) external virtual returns (bytes4) {
        revert();
    }
}
