// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Currency, CurrencyLibrary} from "../libraries/CurrencyLibrary.sol";
import {IERC20Minimal} from "../interfaces/external/IERC20Minimal.sol";

import {ILockCallback} from "../interfaces/callback/ILockCallback.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";

contract PoolBurnTest is ILockCallback {
    using CurrencyLibrary for Currency;

    IPoolManager public immutable manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    // struct CallbackData
    struct CallbackData {
        address sender;
        bool isMint;
        IPoolManager.PoolKey key;
        uint256 amount0;
        uint256 amount1;
    }

    function mint(IPoolManager.PoolKey memory key, uint256 amount0, uint256 amount1) external {
        manager.lock(abi.encode(CallbackData(msg.sender, true, key, amount0, amount1)));
    }

    function burn(IPoolManager.PoolKey memory key, uint256 amount0, uint256 amount1) external {
        manager.lock(abi.encode(CallbackData(msg.sender, false, key, amount0, amount1)));
    }

    function lockAcquired(uint256, bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        if (data.isMint) {
            if (data.amount0 > 0) {
                uint256 currencyBalBefore = IERC20Minimal(Currency.unwrap(data.key.currency0)).balanceOf(data.sender);
                uint256 managerBalBefore = manager.balanceOf(data.sender, data.key.currency0.toId());
                manager.mint(data.key.currency0, data.sender, data.amount0);
                IERC20Minimal(Currency.unwrap(data.key.currency0)).transferFrom(
                    data.sender, address(manager), uint128(data.amount0)
                );
                manager.settle(data.key.currency0);
                uint256 currencyBalAfter = IERC20Minimal(Currency.unwrap(data.key.currency0)).balanceOf(data.sender);
                uint256 managerBalAfter = manager.balanceOf(data.sender, data.key.currency0.toId());
                require(currencyBalBefore - currencyBalAfter == data.amount0);
                require(managerBalAfter - managerBalBefore == data.amount0);
            }
            if (data.amount1 > 0) {
                uint256 currencyBalBefore = IERC20Minimal(Currency.unwrap(data.key.currency1)).balanceOf(data.sender);
                uint256 managerBalBefore = manager.balanceOf(data.sender, data.key.currency1.toId());
                manager.mint(data.key.currency1, data.sender, data.amount1);
                IERC20Minimal(Currency.unwrap(data.key.currency1)).transferFrom(
                    data.sender, address(manager), uint128(data.amount1)
                );
                manager.settle(data.key.currency1);
                uint256 currencyBalAfter = IERC20Minimal(Currency.unwrap(data.key.currency1)).balanceOf(data.sender);
                uint256 managerBalAfter = manager.balanceOf(data.sender, data.key.currency1.toId());
                require(currencyBalBefore - currencyBalAfter == data.amount1);
                require(managerBalAfter - managerBalBefore == data.amount1);
            }
        } else {
            if (data.amount0 > 0) {
                uint256 currencyBalBefore = IERC20Minimal(Currency.unwrap(data.key.currency0)).balanceOf(data.sender);
                uint256 managerBalBefore = manager.balanceOf(data.sender, data.key.currency0.toId());
                manager.take(data.key.currency0, data.sender, data.amount0);
                manager.safeTransferFrom(data.sender, address(manager), data.key.currency0.toId(), data.amount0, "");
                manager.settle(data.key.currency0);
                uint256 currencyBalAfter = IERC20Minimal(Currency.unwrap(data.key.currency0)).balanceOf(data.sender);
                uint256 managerBalAfter = manager.balanceOf(data.sender, data.key.currency0.toId());
                require(currencyBalAfter - currencyBalBefore == data.amount0);
                require(managerBalBefore - managerBalAfter == data.amount0);
            }
            if (data.amount1 > 0) {
                uint256 currencyBalBefore = IERC20Minimal(Currency.unwrap(data.key.currency1)).balanceOf(data.sender);
                uint256 managerBalBefore = manager.balanceOf(data.sender, data.key.currency1.toId());
                manager.take(data.key.currency1, data.sender, data.amount1);
                manager.safeTransferFrom(data.sender, address(manager), data.key.currency1.toId(), data.amount1, "");
                manager.settle(data.key.currency1);
                uint256 currencyBalAfter = IERC20Minimal(Currency.unwrap(data.key.currency1)).balanceOf(data.sender);
                uint256 managerBalAfter = manager.balanceOf(data.sender, data.key.currency1.toId());
                require(currencyBalAfter - currencyBalBefore == data.amount1);
                require(managerBalBefore - managerBalAfter == data.amount1);
            }
        }

        return abi.encode(0);
    }

    function transferToManager(Currency currency, uint256 amount) external {
        manager.safeTransferFrom(msg.sender, address(manager), currency.toId(), amount, "");
    }
}
