// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Currency, CurrencyLibrary} from "../types/Currency.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {IERC20Minimal} from "../interfaces/external/IERC20Minimal.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../types/BalanceDelta.sol";
import {PoolTestBase} from "./PoolTestBase.sol";
import {Test} from "forge-std/Test.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {Hooks} from "../libraries/Hooks.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {PoolIdLibrary, PoolId} from "../types/PoolId.sol";
import {UnsignedSignedMath} from "../libraries/UnsignedSignedMath.sol";

contract PoolDonateTest is PoolTestBase, Test {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using Hooks for IHooks;
    using UnsignedSignedMath for uint128;

    constructor(IPoolManager _manager) PoolTestBase(_manager) {}

    enum DonateType {
        Single,
        Multi
    }

    struct SingleDonateData {
        uint256 amount0;
        uint256 amount1;
    }

    struct SingleOrMultiDonate {
        DonateType donateType;
        address sender;
        PoolKey key;
        bytes hookData;
        bytes variantUniqueData;
    }

    function donate(PoolKey memory key, uint256 amount0, uint256 amount1, bytes memory hookData)
        external
        payable
        returns (BalanceDelta delta)
    {
        delta = abi.decode(
            manager.lock(
                address(this),
                abi.encode(
                    SingleOrMultiDonate(
                        DonateType.Single, msg.sender, key, hookData, abi.encode(SingleDonateData(amount0, amount1))
                    )
                )
            ),
            (BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    function donateMulti(PoolKey calldata key, IPoolManager.MultiDonateParams calldata params, bytes calldata hookData)
        external
        payable
        returns (BalanceDelta delta)
    {
        delta = abi.decode(
            manager.lock(
                address(this),
                abi.encode(SingleOrMultiDonate(DonateType.Multi, msg.sender, key, hookData, abi.encode(params)))
            ),
            (BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    function lockAcquired(address, bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        SingleOrMultiDonate memory data = abi.decode(rawData, (SingleOrMultiDonate));

        (,, uint256 reserveBefore0, int256 deltaBefore0) = _fetchBalances(data.key.currency0, data.sender);
        (,, uint256 reserveBefore1, int256 deltaBefore1) = _fetchBalances(data.key.currency1, data.sender);

        assertEq(deltaBefore0, 0);
        assertEq(deltaBefore1, 0);

        BalanceDelta delta;
        PoolKey memory key = data.key;
        uint256 totalAmount0;
        uint256 totalAmount1;
        if (data.donateType == DonateType.Single) {
            SingleDonateData memory singleData = abi.decode(data.variantUniqueData, (SingleDonateData));
            totalAmount0 = singleData.amount0;
            totalAmount1 = singleData.amount1;
            delta = manager.donate(key, singleData.amount0, singleData.amount1, data.hookData);
        } else if (data.donateType == DonateType.Multi) {
            IPoolManager.MultiDonateParams memory params =
                abi.decode(data.variantUniqueData, (IPoolManager.MultiDonateParams));
            for (uint256 i = 0; i < params.amounts0.length; i++) {
                totalAmount0 += params.amounts0[i];
            }
            for (uint256 i = 0; i < params.amounts1.length; i++) {
                totalAmount1 += params.amounts1[i];
            }
            delta = manager.donate(key, params, data.hookData);
        } else {
            emit log_named_uint("Error: unrecognized DonateType, id", uint8(data.donateType));
            fail();
        }

        // Checks that the current hook is cleared if there is an access lock. Note that if this router is ever used in a nested lock this will fail.
        assertEq(address(manager.getCurrentHook()), address(0));

        (,, uint256 reserveAfter0, int256 deltaAfter0) = _fetchBalances(data.key.currency0, data.sender);
        (,, uint256 reserveAfter1, int256 deltaAfter1) = _fetchBalances(data.key.currency1, data.sender);

        if (!data.key.hooks.hasPermission(Hooks.ACCESS_LOCK_FLAG)) {
            assertEq(reserveBefore0, reserveAfter0);
            assertEq(reserveBefore1, reserveAfter1);
            if (!data.key.hooks.hasPermission(Hooks.NO_OP_FLAG)) {
                assertEq(deltaAfter0, int256(totalAmount0));
                assertEq(deltaAfter1, int256(totalAmount1));
            }
        }

        if (delta == BalanceDeltaLibrary.MAXIMUM_DELTA) {
            // Check that this hook is allowed to NoOp, then we can return as we dont need to settle
            assertTrue(data.key.hooks.hasPermission(Hooks.NO_OP_FLAG), "Invalid NoOp returned");
            return abi.encode(delta);
        }

        if (deltaAfter0 > 0) _settle(data.key.currency0, data.sender, int128(deltaAfter0), true);
        if (deltaAfter1 > 0) _settle(data.key.currency1, data.sender, int128(deltaAfter1), true);
        if (deltaAfter0 < 0) _take(data.key.currency0, data.sender, int128(deltaAfter0), true);
        if (deltaAfter1 < 0) _take(data.key.currency1, data.sender, int128(deltaAfter1), true);

        return abi.encode(delta);
    }
}
