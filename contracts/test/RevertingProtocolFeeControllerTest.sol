// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IProtocolFeeController} from "../interfaces/IProtocolFeeController.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "../types/PoolId.sol";
import {PoolKey} from "../types/PoolKey.sol";

contract RevertingProtocolFeeControllerTest is IProtocolFeeController {
    function protocolFeesForPool(PoolKey memory key) external view returns (uint24) {
        revert();
    }
}
