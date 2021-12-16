// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {IPoolImplementation} from '../../interfaces/IPoolImplementation.sol';
import {IPoolManager} from '../../interfaces/IPoolManager.sol';

abstract contract BasePoolImplementation is IPoolImplementation {
    IPoolManager public immutable override manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    modifier managerOnly() {
        require(msg.sender == address(manager));
        _;
    }
}
