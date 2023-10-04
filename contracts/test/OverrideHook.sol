// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseHooks} from "./BaseHooks.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {ILockCallback} from "../interfaces/callback/ILockCallback.sol";
import {Hooks} from "../libraries/Hooks.sol";
import {CurrencyLibrary, Currency} from "../types/Currency.sol";

import "forge-std/console2.sol";

contract OverrideHook is BaseHooks, ILockCallback {
    using CurrencyLibrary for Currency;

    IPoolManager manager;

    // for testing, but also imagine a hook would keep track of end user balances on LP deposits
    mapping(address => uint256) public lpBalances;

    uint256 exchangeRate;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    function setManager(address _manager) external {
        manager = IPoolManager(_manager);
    }

    function setExchangeRate(uint256 rate) external {
        exchangeRate = rate;
    }

    enum LockAction {
        Deposit,
        Swap
    }

    struct LockCallbackData {
        LockAction action;
        Currency currency0;
        Currency currency1;
        int256 amount;
        address user;
    }

    function lockAcquired(bytes calldata data) external returns (bytes memory) {
        LockCallbackData memory lockData = abi.decode(data, (LockCallbackData));
        if (lockData.action == LockAction.Swap) {
            // mint the amount specified to the hook
            if (lockData.amount > 0) {
                manager.mint(lockData.currency0, address(this), uint256(lockData.amount));
                // credit the pool with currency1
                manager.safeTransferFrom(
                    address(this),
                    address(manager),
                    lockData.currency1.toId(),
                    uint256(lockData.amount) / exchangeRate,
                    ""
                );
                manager.settle(lockData.currency1); // this applies a negative delta that the router can resolve
            }
        } else if (lockData.action == LockAction.Deposit) {
            // just deal with currency1, just handle deposits
            if (lockData.amount > 0) {
                manager.mint(lockData.currency1, address(this), uint256(lockData.amount)); // applies a +amount delta
                lpBalances[lockData.user] += uint256(lockData.amount);
                // The router will settle this unresolved delta
            }
        }
    }

    function beforeModifyPosition(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyPositionParams calldata params,
        bytes calldata hookData
    ) external override returns (bytes4) {
        address user = abi.decode(hookData, (address));

        LockCallbackData memory data = LockCallbackData({
            action: LockAction.Deposit,
            currency0: key.currency0,
            currency1: key.currency1,
            amount: params.liquidityDelta,
            user: user
        });

        bytes memory dataEncoded = abi.encode(data);
        manager.lock(dataEncoded);
        return Hooks.OVERRIDE_SELECTOR;
    }

    function beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) external override returns (bytes4) {
        // Dont really need the end user info for swap, so we set to address(0)
        // create lock call back data struct

        LockCallbackData memory data = LockCallbackData({
            action: LockAction.Swap,
            currency0: key.currency0,
            currency1: key.currency1,
            amount: params.amountSpecified,
            user: address(0)
        });

        manager.lock(abi.encode(data));
        return Hooks.OVERRIDE_SELECTOR;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"));
    }
}
