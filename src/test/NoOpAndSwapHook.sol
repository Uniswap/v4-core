// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Hooks} from "../libraries/Hooks.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {Currency} from "../types/Currency.sol";
import {BaseTestHooks} from "./BaseTestHooks.sol";

contract NoOpAndSwapHook is BaseTestHooks {
    IPoolManager immutable manager;
    PoolKey swapPool;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    // This cannot be in the constructor because after deploy we use `etch` to copy bytecode not storage
    function setSwapPool(PoolKey memory _swapPool) external {
        swapPool = _swapPool;
    }

    modifier onlyPoolManager() {
        require(msg.sender == address(manager));
        _;
    }

    // This hook NoOps swaps and performs the swap itself on another pool. At the end of the new swap
    // The hook has both positive and negative deltas that need to be settled/taken by the user.
    // The hook calls payOnBehalf to transfer the delta it is owed to the router instead
    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata /* hookData **/
    ) external override onlyPoolManager returns (bytes4) {
        require(key.currency0 == swapPool.currency0 || key.currency1 == swapPool.currency1, "Unequal currencies");

        // execute the same swap but on another pool
        BalanceDelta delta = manager.swap(swapPool, params, "");

        // settle the output token for the user, before they claim it
        // this will move the output tokens owed to the hook, to the sender, so they can take them
        // the input tokens owed by the hook will be settled by the sender
        Currency currencyOut = params.zeroForOne ? key.currency1 : key.currency0;
        int256 amountOut = -(params.zeroForOne ? delta.amount1() : delta.amount0());

        // output delta is always negative, so amountOut will be positive
        require(amountOut > 0, "negative amount out");
        manager.payOnBehalf(currencyOut, sender, uint256(amountOut));

        // Now NoOp to stop the original swap from happening
        return Hooks.NO_OP_SELECTOR;
    }
}
