// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {TWAMMHook} from '../hooks/TWAMMHook.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';

contract TWAMMHookTest is TWAMMHook {
    constructor(IPoolManager _poolManager) TWAMMHook(_poolManager) {}

    function getTWAMMExpirationInterval(bytes32 key) external view returns (uint256) {
        return twammStates[key].expirationInterval;
    }

    function getTWAMMLastVOTimestamp(bytes32 key) external view returns (uint256) {
        return twammStates[key].lastVirtualOrderTimestamp;
    }
}
