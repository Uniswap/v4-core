// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {IUnlockCallback} from "../interfaces/callback/IUnlockCallback.sol";

contract PoolEmptyUnlockTest is IUnlockCallback {
    event UnlockCallback();

    IPoolManager manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    function unlock() external {
        manager.unlock("");
    }

    /// @notice Called by the pool manager on `msg.sender` when the manager is unlocked
    function unlockCallback(bytes calldata) external override returns (bytes memory) {
        emit UnlockCallback();
        return "";
    }
}
