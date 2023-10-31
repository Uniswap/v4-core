// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {CurrencyLibrary, Currency} from "../types/Currency.sol";
import {IERC20Minimal} from "../interfaces/external/IERC20Minimal.sol";
import {ILockCallback} from "../interfaces/callback/ILockCallback.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {BalanceDelta} from "../types/BalanceDelta.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {MinimalBalance} from "../MinimalBalance.sol";

contract PoolSwapTest is ILockCallback, MinimalBalance {
    using CurrencyLibrary for Currency;

    IPoolManager public immutable manager;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    struct CallbackData {
        address sender;
        TestSettings testSettings;
        PoolKey key;
        IPoolManager.SwapParams params;
        bytes hookData;
    }

    struct TestSettings {
        bool withdrawTokens;
        bool settleUsingTransfer;
    }

    function swap(
        PoolKey memory key,
        IPoolManager.SwapParams memory params,
        TestSettings memory testSettings,
        bytes memory hookData
    ) external payable returns (BalanceDelta delta) {
        delta = abi.decode(
            manager.lock(abi.encode(CallbackData(msg.sender, testSettings, key, params, hookData))), (BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
    }

    function _mintAndAccountSender(address sender, Currency currency, uint256 amount) internal {
        manager.mint(currency, address(this), amount);
        _mint(sender, currency.toId(), amount);
    }

    function _burnAndAccountSender(address sender, Currency currency, uint256 amount) internal {
        manager.burn(currency, amount);
        _burnFrom(sender, currency.toId(), amount);
    }

    /*
        @notice this router is automatically permissioned to burn tokens from its own Claims mapping
                since swappers must approve the router to spend their tokens
    **/
    function _burnFrom(address from, uint256 id, uint256 amount) internal {
        uint256 balance = balances[id][from];
        if (balance < amount) revert InsufficientBalance();
        unchecked {
            balances[id][from] = balance - amount;
        }
        emit Burn(from, id, amount);
    }

    function lockAcquired(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        BalanceDelta delta = manager.swap(data.key, data.params, data.hookData);

        if (data.params.zeroForOne) {
            if (delta.amount0() > 0) {
                if (data.testSettings.settleUsingTransfer) {
                    if (data.key.currency0.isNative()) {
                        manager.settle{value: uint128(delta.amount0())}(data.key.currency0);
                    } else {
                        IERC20Minimal(Currency.unwrap(data.key.currency0)).transferFrom(
                            data.sender, address(manager), uint128(delta.amount0())
                        );
                        manager.settle(data.key.currency0);
                    }
                } else {
                    // assume router has the tokens
                    _burnAndAccountSender(data.sender, data.key.currency0, uint128(delta.amount0()));
                }
            }
            if (delta.amount1() < 0) {
                if (data.testSettings.withdrawTokens) {
                    manager.take(data.key.currency1, data.sender, uint128(-delta.amount1()));
                } else {
                    _mintAndAccountSender(data.sender, data.key.currency1, uint128(-delta.amount1()));
                }
            }
        } else {
            if (delta.amount1() > 0) {
                if (data.testSettings.settleUsingTransfer) {
                    if (data.key.currency1.isNative()) {
                        manager.settle{value: uint128(delta.amount1())}(data.key.currency1);
                    } else {
                        IERC20Minimal(Currency.unwrap(data.key.currency1)).transferFrom(
                            data.sender, address(manager), uint128(delta.amount1())
                        );
                        manager.settle(data.key.currency1);
                    }
                } else {
                    _burnAndAccountSender(data.sender, data.key.currency1, uint128(delta.amount1()));
                }
            }
            if (delta.amount0() < 0) {
                if (data.testSettings.withdrawTokens) {
                    manager.take(data.key.currency0, data.sender, uint128(-delta.amount0()));
                } else {
                    _mintAndAccountSender(data.sender, data.key.currency0, uint128(-delta.amount0()));
                }
            }
        }

        return abi.encode(delta);
    }
}
