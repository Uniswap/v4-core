// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IProtocolFeeController} from "../interfaces/IProtocolFeeController.sol";
import {PoolId} from "../types/PoolId.sol";
import {PoolKey} from "../types/PoolKey.sol";

contract ProtocolFeeControllerTest is IProtocolFeeController {
    mapping(PoolId => uint24) public protocolFee;

    function protocolFeeForPool(PoolKey memory key) external view returns (uint24) {
        return protocolFee[key.toId()];
    }

    // for tests to set pool protocol fees
    function setProtocolFeeForPool(PoolId id, uint24 fee) external {
        protocolFee[id] = fee;
    }
}
