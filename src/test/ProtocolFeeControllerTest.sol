// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IProtocolFeeController} from "../interfaces/IProtocolFeeController.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "../types/PoolId.sol";
import {PoolKey} from "../types/PoolKey.sol";

contract ProtocolFeeControllerTest is IProtocolFeeController {
    using PoolIdLibrary for PoolKey;

    mapping(PoolId => uint16) public swapFeeForPool;
    mapping(PoolId => uint16) public withdrawFeeForPool;

    function protocolFeesForPool(PoolKey memory key) external view returns (uint24) {
        return (uint24(swapFeeForPool[key.toId()]) << 12 | withdrawFeeForPool[key.toId()]);
    }

    // for tests to set pool protocol fees
    function setSwapFeeForPool(PoolId id, uint16 fee) external {
        swapFeeForPool[id] = fee;
    }

    function setWithdrawFeeForPool(PoolId id, uint16 fee) external {
        withdrawFeeForPool[id] = fee;
    }
}

/// @notice Reverts on call
contract RevertingProtocolFeeControllerTest is IProtocolFeeController {
    function protocolFeesForPool(PoolKey memory /* key */ ) external view returns (uint24) {
        revert();
    }
}

/// @notice Returns an out of bounds protocol fee
contract OutOfBoundsProtocolFeeControllerTest is IProtocolFeeController {
    function protocolFeesForPool(PoolKey memory /* key */ ) external view returns (uint24) {
        // set both swap and withdraw fees to 1, which is less than MIN_PROTOCOL_FEE_DENOMINATOR
        return 0x001001;
    }
}

/// @notice Return a value that overflows a uint24
contract OverflowProtocolFeeControllerTest is IProtocolFeeController {
    function protocolFeesForPool(PoolKey memory /* key */ ) external view returns (uint24) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0xFFFFAAA001)
            return(ptr, 0x20)
        }
    }
}

/// @notice Returns data that is larger than a word
contract InvalidReturnSizeProtocolFeeControllerTest is IProtocolFeeController {
    function protocolFeesForPool(PoolKey memory /* key */ ) external view returns (uint24) {
        address a = address(this);
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, a)
            mstore(add(ptr, 0x20), a)
            return(ptr, 0x20)
        }
    }
}
