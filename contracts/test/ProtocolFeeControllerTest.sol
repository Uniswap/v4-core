// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.13;

import {IProtocolFeeController} from '../interfaces/IProtocolFeeController.sol';

contract ProtocolFeeControllerTest is IProtocolFeeController {
    mapping(bytes32 => uint8) public feeForPool;

    function protocolFeeForPool(bytes32 key) external view returns (uint8) {
        return feeForPool[key];
    }

    // for tests to set pool protocol fees
    function setFeeForPool(bytes32 key, uint8 fee) external {
        feeForPool[key] = fee;
    }
}
