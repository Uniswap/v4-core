// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Hooks} from "../libraries/Hooks.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {BalanceDelta, toBalanceDelta} from "../types/BalanceDelta.sol";
import {IHookFeeManager} from "../interfaces/IHookFeeManager.sol";
import {PoolId, PoolIdLibrary} from "../types/PoolId.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {CurrencyLibrary, Currency} from "../types/Currency.sol";
import {IERC20Minimal} from "../interfaces/external/IERC20Minimal.sol";
import {ILockCallback} from "../interfaces/callback/ILockCallback.sol";

contract NoOpTestHooks is IHooks, IHookFeeManager, IERC1155Receiver, ILockCallback {
    using PoolIdLibrary for PoolKey;
    using Hooks for IHooks;
    using CurrencyLibrary for Currency;

    IPoolManager manager;

    mapping(bytes4 => bytes4) public returnValues;

    mapping(PoolId => uint8) public swapFees;

    mapping(PoolId => uint8) public withdrawFees;

    struct CallbackData {
        address sender;
        PoolKey key;
        uint160 sqrtPriceX96;
    }

    constructor() {
        IHooks(this).validateHookAddress(
            Hooks.Calls({
                beforeInitialize: true,
                afterInitialize: false,
                beforeModifyPosition: true,
                afterModifyPosition: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: true,
                afterDonate: false
            })
        );
    }

    function initialize(IPoolManager _manager, PoolKey memory key, uint160 sqrtPriceX96) external {
        manager = _manager;
        abi.decode(manager.lock(abi.encode(CallbackData(msg.sender, key, sqrtPriceX96))), (BalanceDelta));

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    function lockAcquired(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        // TODO: rename lol
        uint256 prev0of1155 = manager.balanceOf(address(this), CurrencyLibrary.toId(data.key.currency0));
        uint256 prev1of1155 = manager.balanceOf(address(this), CurrencyLibrary.toId(data.key.currency1));

        manager.initialize(data.key, data.sqrtPriceX96);

        uint256 amount0Owe = manager.balanceOf(address(this), CurrencyLibrary.toId(data.key.currency0)) - prev0of1155;
        uint256 amount1Owe = manager.balanceOf(address(this), CurrencyLibrary.toId(data.key.currency1)) - prev1of1155;

        if (data.key.currency0.isNative()) {
            manager.settle{value: uint128(amount0Owe)}(data.key.currency0);
        } else {
            IERC20Minimal(Currency.unwrap(data.key.currency0)).transferFrom(data.sender, address(manager), amount0Owe);
            manager.settle(data.key.currency0);
        }

        if (data.key.currency1.isNative()) {
            manager.settle{value: uint128(amount1Owe)}(data.key.currency1);
        } else {
            IERC20Minimal(Currency.unwrap(data.key.currency1)).transferFrom(
                data.sender, address(manager), uint128(amount1Owe)
            );
            manager.settle(data.key.currency1);
        }

        return abi.encode(toBalanceDelta(int128(int256(amount0Owe)), int128(int256(amount1Owe))));
    }

    function beforeInitialize(address caller, PoolKey memory, uint160) external override returns (bytes32) {
        // 0xAAAAAAAA_00000............. padding of bytes4
        // 112 bits per amount in BalanceDelta, 224 bits total since 256 - 32 = 224, as bytes4 takes up 32 bits
        int112 amt0 = 1 ether;
        int112 amt1 = 0 ether;

        bytes32 selector = IHooks.beforeInitialize.selector;

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

    function afterInitialize(address, PoolKey memory, uint160, int24) external pure override returns (bytes4) {
        return bytes4(0);
    }

    function beforeModifyPosition(address, PoolKey calldata key, IPoolManager.ModifyPositionParams calldata params)
        external
        override
        returns (bytes32)
    {
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

    function afterModifyPosition(address, PoolKey calldata, IPoolManager.ModifyPositionParams calldata, BalanceDelta)
        external
        pure
        override
        returns (bytes4)
    {
        return bytes4(0);
    }

    function beforeSwap(address caller, PoolKey calldata, IPoolManager.SwapParams calldata)
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

    function afterSwap(address, PoolKey calldata, IPoolManager.SwapParams calldata, BalanceDelta)
        external
        pure
        override
        returns (bytes4)
    {
        return bytes4(0);
    }

    function beforeDonate(address caller, PoolKey calldata, uint256 amount1, uint256 amount0)
        external
        override
        returns (bytes32)
    {
        // 0xAAAAAAAA_00000............. padding of bytes4
        // 112 bits per amount in BalanceDelta, 224 bits total since 256 - 32 = 224, as bytes4 takes up 32 bits
        bytes32 selector = Hooks.NO_OP;
        int112 amt0 = 1 ether + int112(int256(amount0));
        int112 amt1 = 1 ether + int112(int256(amount1));

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

    function afterDonate(address, PoolKey calldata, uint256, uint256) external pure override returns (bytes4) {
        return bytes4(0);
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
