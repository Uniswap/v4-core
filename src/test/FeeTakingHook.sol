// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Hooks} from "../libraries/Hooks.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {Currency} from "../types/Currency.sol";
import {BaseTestHooks} from "./BaseTestHooks.sol";

contract FeeTakingHook is BaseTestHooks {
    using Hooks for IHooks;

    IPoolManager manager;

    constructor(IPoolManager _manager) {
        manager = _manager;

        IHooks(this).validateHookPermissions(
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                noOp: false
            })
        );
    }

    modifier onlyPoolManager() {
        require(msg.sender == address(manager));
        _;
    }
    
    uint256 constant WITHDRAWAL_FEE_BIPS = 40; // 40/10000 = 0.4%
    uint256 constant SWAP_FEE_BIPS = 55; // 55/10000 = 0.55%
    uint256 constant TOTAL_BIPS = 10000;

    function afterRemoveLiquidity(
        address, /* sender **/
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata, /* params **/
        BalanceDelta delta,
        bytes calldata /* hookData **/
    ) external override onlyPoolManager returns (bytes4) {
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();

        // negative delta => user is owed money => liquidity withdrawal
        uint256 amount0Fee = uint128(-amount0) * WITHDRAWAL_FEE_BIPS / TOTAL_BIPS;
        uint256 amount1Fee = uint128(-amount1) * WITHDRAWAL_FEE_BIPS / TOTAL_BIPS;

        manager.take(key.currency0, address(this), amount0Fee);
        manager.take(key.currency1, address(this), amount1Fee);

        return IHooks.afterRemoveLiquidity.selector;
    }

    function afterSwap(
        address, /* sender **/
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata /* hookData **/
    ) external override onlyPoolManager returns (bytes4) {
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();

        // fee on output token - output delta will be negative
        (Currency feeCurrency, uint256 outputAmount) =
            (params.zeroForOne) ? (key.currency1, uint128(-amount1)) : (key.currency0, uint128(-amount0));

        uint256 feeAmount = outputAmount * SWAP_FEE_BIPS / TOTAL_BIPS;

        manager.take(feeCurrency, address(this), feeAmount);

        return IHooks.afterSwap.selector;
    }
}