// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IProtocolFeeController} from "../interfaces/IProtocolFeeController.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "../libraries/PoolId.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

contract ProtocolFeeControllerTest is IProtocolFeeController {
    using PoolIdLibrary for IPoolManager.PoolKey;

    mapping(PoolId => uint8) public swapFeeForPool;
    mapping(PoolId => uint8) public withdrawFeeForPool;

    function protocolFeesForPool(IPoolManager.PoolKey memory key) external view returns (uint8, uint8) {
        return (swapFeeForPool[key.toId()], withdrawFeeForPool[key.toId()]);
    }

    // for tests to set pool protocol fees
    function setSwapFeeForPool(PoolId id, uint8 fee) external {
        swapFeeForPool[id] = fee;
    }

    function setWithdrawFeeForPool(PoolId id, uint8 fee) external {
        withdrawFeeForPool[id] = fee;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }
}
