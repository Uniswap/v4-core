// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IProtocolFeeController} from "../interfaces/IProtocolFeeController.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolId} from "../libraries/PoolId.sol";

contract ProtocolFeeControllerTest is IProtocolFeeController {
    using PoolId for IPoolManager.PoolKey;

    mapping(bytes32 => uint8) public swapFeeForPool;
    mapping(bytes32 => uint8) public withdrawFeeForPool;

    function protocolFeesForPool(IPoolManager.PoolKey memory key) external view returns (uint8, uint8) {
        return (swapFeeForPool[key.toId()], withdrawFeeForPool[key.toId()]);
    }

    // for tests to set pool protocol fees
    function setSwapFeeForPool(bytes32 id, uint8 fee) external {
        swapFeeForPool[id] = fee;
    }

    function setWithdrawFeeForPool(bytes32 id, uint8 fee) external {
        withdrawFeeForPool[id] = fee;
    }
}
