// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Hooks} from "../libraries/Hooks.sol";
import {SafeCast} from "../libraries/SafeCast.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {Currency} from "../types/Currency.sol";
import {BaseTestHooks} from "./BaseTestHooks.sol";

contract FeeTakingHook is BaseTestHooks {
    using Hooks for IHooks;
    using SafeCast for uint256;
    using SafeCast for int128;

    IPoolManager immutable manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    modifier onlyPoolManager() {
        require(msg.sender == address(manager));
        _;
    }

    uint256 public constant SWAP_FEE_BIPS = 123; // 123/10000 = 1.23%
    uint256 public constant TOTAL_BIPS = 10000;

    function afterSwap(
        address, /* sender **/
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata /* hookData **/
    ) external override onlyPoolManager returns (bytes4, int128) {
        // fee will be in the unspecified token of the swap
        bool specifiedTokenIs0 = (params.amountSpecified > 0 == params.zeroForOne);
        (Currency feeCurrency, int128 swapAmount) =
            (specifiedTokenIs0) ? (key.currency1, delta.amount1()) : (key.currency0, delta.amount0());

        // if fee is on output, get the absolute output amount
        if (swapAmount < 0) swapAmount = -swapAmount;

        uint256 feeAmount = uint128(swapAmount) * SWAP_FEE_BIPS / TOTAL_BIPS;
        manager.take(feeCurrency, address(this), feeAmount);

        return (IHooks.afterSwap.selector, feeAmount.toInt128());
    }
}
