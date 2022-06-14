// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {IProtocolFeeController} from '../interfaces/IProtocolFeeController.sol';
import {IPoolManager} from '../interfaces/IPoolManager.sol';

contract ProtocolFeeControllerTest is IProtocolFeeController {
    mapping(bytes32 => uint8) public feeForPool;

    function protocolFeeForPool(bytes32 id) external view returns (uint8) {
        return feeForPool[id];
    }

    // for tests to set pool protocol fees
    function setFeeForPool(bytes32 id, uint8 fee) external {
        feeForPool[id] = fee;
    }
}
