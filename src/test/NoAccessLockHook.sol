// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTestHooks} from "./BaseTestHooks.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {IHooks} from "../interfaces/IHooks.sol";

contract NoAccessLockHook is BaseTestHooks {
    IPoolManager manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    function beforeModifyPosition(
        address, /* sender **/
        PoolKey calldata key,
        IPoolManager.ModifyPositionParams calldata, /* params **/
        bytes calldata /* hookData **/
    ) external override returns (bytes4) {
        // This should revert.
        manager.mint(key.currency0, address(this), 100 * 10e18);
        return IHooks.beforeModifyPosition.selector;
    }
}
