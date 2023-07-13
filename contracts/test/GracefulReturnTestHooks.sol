// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Hooks} from "../libraries/Hooks.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {IHookFeeManager} from "../interfaces/IHookFeeManager.sol";
import {PoolId, PoolIdLibrary} from "../types/PoolId.sol";
import {PoolKey} from "../types/PoolKey.sol";

contract GracefulReturnTestHooks is IHooks, IHookFeeManager {
    using PoolIdLibrary for PoolKey;
    using Hooks for IHooks;

    mapping(bytes4 => bytes4) public returnValues;

    mapping(PoolId => uint8) public swapFees;

    mapping(PoolId => uint8) public withdrawFees;

    enum Stage {
        Null,
        Initialize,
        Modify,
        Swap,
        Donate
    }

    struct CallerQueue {
        address caller;
        uint64 nonce;
        uint8 stage;
        bytes32 head;
    }

    CallerQueue public queue;
    address public lastCaller;

    constructor() {
        IHooks(this).validateHookAddress(
            Hooks.Calls({
                beforeInitialize: true,
                afterInitialize: true,
                beforeModifyPosition: true,
                afterModifyPosition: true,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: true,
                afterDonate: true
            })
        );

        queue = CallerQueue({caller: address(0), nonce: 0, stage: uint8(Stage.Null), head: bytes32(0)});
        lastCaller = address(0);
    }

    function beforeInitialize(address caller, PoolKey memory, uint160) external override returns (bytes32) {
        CallerQueue memory previous = queue;

        queue = CallerQueue({
            caller: caller,
            nonce: previous.nonce + 1,
            stage: uint8(Stage.Initialize),
            head: keccak256(abi.encode(previous))
        });

        lastCaller = caller;

        return IHooks.beforeInitialize.selector;
    }

    function afterInitialize(address, PoolKey memory, uint160, int24) external pure override returns (bytes4) {
        return IHooks.afterInitialize.selector;
    }

    function beforeModifyPosition(address caller, PoolKey calldata, IPoolManager.ModifyPositionParams calldata)
        external
        override
        returns (bytes32)
    {
        CallerQueue memory previous = queue;

        queue = CallerQueue({
            caller: caller,
            nonce: previous.nonce + 1,
            stage: uint8(Stage.Modify),
            head: keccak256(abi.encode(previous))
        });

        lastCaller = caller;

        return IHooks.beforeModifyPosition.selector;
    }

    function afterModifyPosition(address, PoolKey calldata, IPoolManager.ModifyPositionParams calldata, BalanceDelta)
        external
        pure
        override
        returns (bytes4)
    {
        return IHooks.afterModifyPosition.selector;
    }

    function beforeSwap(address caller, PoolKey calldata, IPoolManager.SwapParams calldata)
        external
        override
        returns (bytes32)
    {
        CallerQueue memory previous = queue;

        queue = CallerQueue({
            caller: caller,
            nonce: previous.nonce + 1,
            stage: uint8(Stage.Swap),
            head: keccak256(abi.encode(previous))
        });

        lastCaller = caller;

        return IHooks.beforeSwap.selector;
    }

    function afterSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, BalanceDelta)
        external
        pure
        override
        returns (bytes4)
    {
        return IHooks.afterSwap.selector;
    }

    function beforeDonate(address caller, PoolKey calldata, uint256, uint256) external override returns (bytes32) {
        CallerQueue memory previous = queue;

        queue = CallerQueue({
            caller: caller,
            nonce: previous.nonce + 1,
            stage: uint8(Stage.Donate),
            head: keccak256(abi.encode(previous))
        });

        lastCaller = caller;

        return IHooks.beforeDonate.selector;
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256) external pure override returns (bytes4) {
        return IHooks.afterDonate.selector;
    }

    function getHookSwapFee(PoolKey calldata key) external view override returns (uint8) {
        return swapFees[key.toId()];
    }

    function getHookWithdrawFee(PoolKey calldata key) external view override returns (uint8) {
        return withdrawFees[key.toId()];
    }

    function setReturnValue(bytes4 key, bytes4 value) external {
        returnValues[key] = value;
    }

    function setSwapFee(PoolKey calldata key, uint8 value) external {
        swapFees[key.toId()] = value;
    }

    function setWithdrawFee(PoolKey calldata key, uint8 value) external {
        withdrawFees[key.toId()] = value;
    }

    function simulateHead(address caller, uint256 nonce, uint256 stage, bytes32 head) external pure returns (bytes32) {
        CallerQueue memory previous =
            CallerQueue({caller: caller, nonce: uint64(nonce), stage: uint8(stage), head: head});
        return keccak256(abi.encode(previous));
    }

    function simulateQueueFullCycle(address initializer, address positionModifier, address swapper, address donor)
        external
        pure
        returns (bytes32)
    {
        CallerQueue memory previous =
            CallerQueue({caller: address(0), nonce: 0, stage: uint8(Stage.Null), head: bytes32(0)});

        previous = CallerQueue({
            caller: initializer,
            nonce: previous.nonce + 1,
            stage: uint8(Stage.Initialize),
            head: keccak256(abi.encode(previous))
        });

        previous = CallerQueue({
            caller: positionModifier,
            nonce: previous.nonce + 1,
            stage: uint8(Stage.Modify),
            head: keccak256(abi.encode(previous))
        });

        previous = CallerQueue({
            caller: swapper,
            nonce: previous.nonce + 1,
            stage: uint8(Stage.Swap),
            head: keccak256(abi.encode(previous))
        });

        previous = CallerQueue({
            caller: donor,
            nonce: previous.nonce + 1,
            stage: uint8(Stage.Donate),
            head: keccak256(abi.encode(previous))
        });

        return keccak256(abi.encode(previous));
    }

    function checkHead() public view returns (bytes32 head) {
        CallerQueue memory previous = queue;
        return keccak256(abi.encode(previous));
    }
}
