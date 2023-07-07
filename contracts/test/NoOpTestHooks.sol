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
                beforeModifyPosition: false,
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
        returns (bytes4)
    {
        return bytes4(0);
    }

    function afterInitialize(address, IPoolManager.PoolKey memory, uint160, int24)
        external
        pure
        override
        returns (bytes4)
    {
        return bytes4(0);
    }

    function beforeModifyPosition(address, IPoolManager.PoolKey calldata, IPoolManager.ModifyPositionParams calldata)
        external
        override
        returns (bytes4)
    {
        return bytes4(0);
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
        returns (bytes4, BalanceDelta)
    {
        return (Hooks.RETURN_BEFORE_SWAP, toBalanceDelta(1 ether, -1 ether));
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
        returns (bytes4)
    {
        return bytes4(0);
    }

    function afterDonate(address, IPoolManager.PoolKey calldata, uint256, uint256)
        external
        pure
        override
        returns (bytes4)
    {
        return bytes4(0);
    }

    struct CallbackData {
        address sender;
        IPoolManager.PoolKey key;
        int128 amount0;
        int128 amount1;
    }

    function modifyLiquidity(IPoolManager.PoolKey memory key, int128 amount0, int128 amount1)
        external
        payable
        returns (BalanceDelta delta)
    {
        delta = abi.decode(manager.lock(abi.encode(CallbackData(msg.sender, key, amount0, amount1))), (BalanceDelta));

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    function lockAcquired(uint256, bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        if (data.amount0 > 0) {
            manager.mint(data.key.currency0, address(this), uint128(data.amount0));
            if (data.key.currency0.isNative()) {
                manager.settle{value: uint128(data.amount0)}(data.key.currency0);
            } else {
                IERC20Minimal(Currency.unwrap(data.key.currency0)).transferFrom(
                    data.sender, address(manager), uint128(data.amount0)
                );
                manager.settle(data.key.currency0);
            }
        }
        if (data.amount1 > 0) {
            manager.mint(data.key.currency1, address(this), uint128(data.amount1));
            if (data.key.currency1.isNative()) {
                manager.settle{value: uint128(data.amount1)}(data.key.currency1);
            } else {
                IERC20Minimal(Currency.unwrap(data.key.currency1)).transferFrom(
                    data.sender, address(manager), uint128(data.amount1)
                );
                manager.settle(data.key.currency1);
            }
        }

        if (data.amount0 < 0) {
            // TODO: approve the manager for the transfer
            manager.safeTransferFrom(
                address(this), address(manager), data.key.currency0.toId(), uint128(-data.amount0), ""
            );
            manager.take(data.key.currency0, data.sender, uint128(-data.amount0));
        }
        if (data.amount1 < 0) {
            manager.safeTransferFrom(
                address(this), address(manager), data.key.currency1.toId(), uint128(-data.amount1), ""
            );
            manager.take(data.key.currency1, data.sender, uint128(-data.amount1));
        }

        return abi.encode(toBalanceDelta(int128(int256(data.amount0)), int128(int256(data.amount1))));
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
