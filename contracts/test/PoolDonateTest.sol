// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Currency, CurrencyLibrary} from "../types/Currency.sol";
import {IERC20Minimal} from "../interfaces/external/IERC20Minimal.sol";

import {Currency} from "../types/Currency.sol";
import {ILockCallback} from "../interfaces/callback/ILockCallback.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";

contract PoolDonateTest is ILockCallback {
    using CurrencyLibrary for Currency;

    IPoolManager public immutable manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    struct CallbackData {
        address sender;
        PoolKey key;
        uint256 amount0;
        uint256 amount1;
    }

    struct CallbackDataRange {
        address sender;
        PoolKey key;
        uint256[] amounts0;
        uint256[] amounts1;
        int24[] ticks;
    }

    struct DonateData {
        DonateType donateType;
        bytes callbackData;
    }

    enum DonateType {
        Single,
        Range
    }

    function donate(PoolKey memory key, uint256 amount0, uint256 amount1)
        external
        payable
        returns (BalanceDelta delta)
    {
        bytes memory data =
            abi.encode(DonateData(DonateType.Single, abi.encode(CallbackData(msg.sender, key, amount0, amount1))));
        delta = abi.decode(manager.lock(data), (BalanceDelta));

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    function donateRange(
        PoolKey memory key,
        uint256[] calldata amounts0,
        uint256[] calldata amounts1,
        int24[] calldata ticks
    ) external payable returns (BalanceDelta delta) {
        bytes memory data = abi.encode(
            DonateData(DonateType.Range, abi.encode(CallbackDataRange(msg.sender, key, amounts0, amounts1, ticks)))
        );
        delta = abi.decode(manager.lock(data), (BalanceDelta));

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    function lockAcquired(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        DonateData memory donateData = abi.decode(rawData, (DonateData));

        BalanceDelta delta;
        PoolKey memory key;
        address sender;
        if (donateData.donateType == DonateType.Single) {
            CallbackData memory data = abi.decode(donateData.callbackData, (CallbackData));
            key = data.key;
            sender = data.sender;
            delta = manager.donate(data.key, data.amount0, data.amount1, new bytes(0));
        } else if (donateData.donateType == DonateType.Range) {
            CallbackDataRange memory data = abi.decode(donateData.callbackData, (CallbackDataRange));
            key = data.key;
            sender = data.sender;
            delta = manager.donate(data.key, data.amounts0, data.amounts1, data.ticks, new bytes(0));
        }

        if (delta.amount0() > 0) {
            if (key.currency0.isNative()) {
                manager.settle{value: uint128(delta.amount0())}(key.currency0);
            } else {
                IERC20Minimal(Currency.unwrap(key.currency0)).transferFrom(
                    sender, address(manager), uint128(delta.amount0())
                );
                manager.settle(key.currency0);
            }
        }
        if (delta.amount1() > 0) {
            if (key.currency1.isNative()) {
                manager.settle{value: uint128(delta.amount1())}(key.currency1);
            } else {
                IERC20Minimal(Currency.unwrap(key.currency1)).transferFrom(
                    sender, address(manager), uint128(delta.amount1())
                );
                manager.settle(key.currency1);
            }
        }

        return abi.encode(delta);
    }
}
