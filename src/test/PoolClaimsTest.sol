// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Currency, CurrencyLibrary} from "../types/Currency.sol";
import {BalanceDelta, toBalanceDelta} from "../types/BalanceDelta.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {PoolTestBase} from "./PoolTestBase.sol";
import {SafeCast} from "../libraries/SafeCast.sol";
import {Test} from "forge-std/Test.sol";

contract PoolClaimsTest is PoolTestBase {
    using CurrencyLibrary for Currency;
    using SafeCast for uint256;

    constructor(IPoolManager _manager) PoolTestBase(_manager) {}

    struct CallbackData {
        address sender;
        address user;
        Currency currency;
        uint256 amount;
        bool deposit;
    }

    /// @notice Convert ERC20 into a claimable 6909
    function deposit(Currency currency, address user, uint256 amount) external payable {
        manager.lock(abi.encode(CallbackData(msg.sender, user, currency, amount, true)));
    }

    /// @notice Redeem claimable 6909 for ERC20
    function withdraw(Currency currency, address user, uint256 amount) external payable {
        manager.lock(abi.encode(CallbackData(msg.sender, user, currency, amount, false)));
    }

    function lockAcquired(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        if (data.deposit) {
            manager.mint(data.user, data.currency.toId(), uint128(data.amount));
            _settle(data.currency, data.user, -data.amount.toInt128(), true);
        } else {
            manager.burn(data.user, data.currency.toId(), uint128(data.amount));
            _take(data.currency, data.user, data.amount.toInt128(), true);
        }

        return abi.encode(0);
    }
}
