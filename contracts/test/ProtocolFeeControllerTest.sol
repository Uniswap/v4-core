// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {IProtocolFeeController} from "../interfaces/IProtocolFeeController.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolId} from "../libraries/PoolId.sol";

contract ProtocolFeeControllerTest is IProtocolFeeController {
    using PoolId for IPoolManager.PoolKey;

    mapping(bytes32 => uint8) public feeForPool;

    function protocolFeeForPool(IPoolManager.PoolKey memory key) external view returns (uint8, uint8) {
        // TODO test positive withdraw fee
        return (feeForPool[key.toId()], 0);
    }

    // for tests to set pool protocol fees
    function setFeeForPool(bytes32 id, uint8 fee) external {
        feeForPool[id] = fee;
    }
}
