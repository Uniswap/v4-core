// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IProtocolFeeController} from "../interfaces/IProtocolFeeController.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "../types/PoolId.sol";
import {PoolKey} from "../types/PoolKey.sol";

contract ProtocolFeeControllerTest is IProtocolFeeController {
    using PoolIdLibrary for PoolKey;

    mapping(PoolId => uint8) public swapFeeForPool;
    mapping(PoolId => uint8) public withdrawFeeForPool;

    function protocolFeesForPool(PoolKey memory key) external view returns (uint8, uint8) {
        return (swapFeeForPool[key.toId()], withdrawFeeForPool[key.toId()]);
    }

    // for tests to set pool protocol fees
    function setSwapFeeForPool(PoolId id, uint8 fee) external {
        swapFeeForPool[id] = fee;
    }

    function setWithdrawFeeForPool(PoolId id, uint8 fee) external {
        withdrawFeeForPool[id] = fee;
    }
}
