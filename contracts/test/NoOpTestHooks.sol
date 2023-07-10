// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Hooks} from "../libraries/Hooks.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {BalanceDelta, toBalanceDelta} from "../types/BalanceDelta.sol";
import {IHookFeeManager} from "../interfaces/IHookFeeManager.sol";
import {PoolId, PoolIdLibrary} from "../libraries/PoolId.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {CurrencyLibrary, Currency} from "../libraries/CurrencyLibrary.sol";
import {IERC20Minimal} from "../interfaces/external/IERC20Minimal.sol";
import {ILockCallback} from "../interfaces/callback/ILockCallback.sol";

contract NoOpTestHooks is IHooks, IHookFeeManager, IERC1155Receiver {
    using PoolIdLibrary for IPoolManager.PoolKey;
    using Hooks for IHooks;
    using CurrencyLibrary for Currency;

    IPoolManager public manager;

    mapping(bytes4 => bytes4) public returnValues;

    mapping(PoolId => uint8) public swapFees;

    mapping(PoolId => uint8) public withdrawFees;

    constructor() {
        IHooks(this).validateHookAddress(
            Hooks.Calls({
                beforeInitialize: false,
                afterInitialize: false,
                beforeModifyPosition: true,
                afterModifyPosition: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
            })
        );
    }

    function setManager(IPoolManager _manager) external {
        manager = _manager;
    }

    function beforeInitialize(address caller, IPoolManager.PoolKey memory, uint160)
        external
        override
        returns (bytes32)
    {
        return bytes32(0);
    }

    function afterInitialize(address, IPoolManager.PoolKey memory, uint160, int24)
        external
        pure
        override
        returns (bytes4)
    {
        return bytes4(0);
    }

    function beforeModifyPosition(
        address,
        IPoolManager.PoolKey calldata key,
        IPoolManager.ModifyPositionParams calldata params
    ) external override returns (bytes32) {
        bytes32 selector = Hooks.NO_OP;
        int112 amt = int112(params.liquidityDelta);

        /// @solidity memory-safe-assembly
        assembly {
            // 0xAAAAAAAA_112 bits of amt0, 112 bits of amt1
            selector :=
                or(
                    selector,
                    or(
                        and(0x00000000ffffffffffffffffffffffffffff0000000000000000000000000000, shl(112, amt)),
                        and(0x000000000000000000000000000000000000ffffffffffffffffffffffffffff, amt)
                    )
                )
        }
        return selector;
    }

    function afterModifyPosition(
        address,
        IPoolManager.PoolKey calldata,
        IPoolManager.ModifyPositionParams calldata,
        BalanceDelta
    ) external pure override returns (bytes4) {
        return bytes4(0);
    }

    function beforeSwap(address caller, IPoolManager.PoolKey calldata, IPoolManager.SwapParams calldata)
        external
        override
        returns (bytes32)
    {
        // 0xAAAAAAAA_00000............. padding of bytes4
        // 112 bits per amount in BalanceDelta, 224 bits total since 256 - 32 = 224, as bytes4 takes up 32 bits
        bytes32 selector = Hooks.NO_OP;
        int112 amt0 = 1 ether;
        int112 amt1 = -1 ether;

        /// @solidity memory-safe-assembly
        assembly {
            // 0xAAAAAAAA_112 bits of amt0, 112 bits of amt1
            selector :=
                or(
                    selector,
                    or(and(0x00000000ffffffffffffffffffffffffffff0000000000000000000000000000, shl(112, amt1)), amt0)
                )
        }
        return selector;
    }

    function afterSwap(address, IPoolManager.PoolKey calldata, IPoolManager.SwapParams calldata, BalanceDelta)
        external
        pure
        override
        returns (bytes4)
    {
        return bytes4(0);
    }

    function beforeDonate(address caller, IPoolManager.PoolKey calldata, uint256, uint256)
        external
        override
        returns (bytes32)
    {
        return bytes32(0);
    }

    function afterDonate(address, IPoolManager.PoolKey calldata, uint256, uint256)
        external
        pure
        override
        returns (bytes4)
    {
        return bytes4(0);
    }

    function getHookSwapFee(IPoolManager.PoolKey calldata key) external view override returns (uint8) {
        return swapFees[key.toId()];
    }

    function getHookWithdrawFee(IPoolManager.PoolKey calldata key) external view override returns (uint8) {
        return withdrawFees[key.toId()];
    }

    function setReturnValue(bytes4 key, bytes4 value) external {
        returnValues[key] = value;
    }

    function setSwapFee(IPoolManager.PoolKey calldata key, uint8 value) external {
        swapFees[key.toId()] = value;
    }

    function setWithdrawFee(IPoolManager.PoolKey calldata key, uint8 value) external {
        withdrawFees[key.toId()] = value;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"));
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"));
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}
