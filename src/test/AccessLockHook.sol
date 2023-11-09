// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTestHooks} from "./BaseTestHooks.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {CurrencyLibrary, Currency} from "../types/Currency.sol";
import {Hooks} from "../libraries/Hooks.sol";

import "forge-std/console2.sol";

contract AccessLockHook is BaseTestHooks {
    using CurrencyLibrary for Currency;

    IPoolManager manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    function beforeModifyPosition(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyPositionParams calldata params,
        bytes calldata hookData
    ) external override returns (bytes4) {
        // just deal with positive deposits of currency1
        (uint256 amount1) = abi.decode(hookData, (uint256));
        manager.mint(key.currency1, address(this), amount1);
        return Hooks.OVERRIDE_SELECTOR;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes memory) public returns (bytes4) {
        return this.onERC1155Received.selector;
    }
}
