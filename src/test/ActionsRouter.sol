// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {IUnlockCallback} from "../interfaces/callback/IUnlockCallback.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../types/BalanceDelta.sol";

import {Currency} from "../types/Currency.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {StateLibrary} from "../libraries/StateLibrary.sol";
import {TransientStateLibrary} from "../libraries/TransientStateLibrary.sol";
import {PoolId, PoolIdLibrary} from "src/types/PoolId.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {IHooks} from "src/interfaces/IHooks.sol";
import {PoolKey} from "src/types/PoolKey.sol";
import {IActionsHarness} from "../../test/trailofbits/IActionsHarness.sol";

// Supported Actions.
enum Actions {
    SETTLE,
    SETTLE_NATIVE,
    SETTLE_FOR,
    TAKE,
    PRANK_TAKE_FROM,
    SYNC,
    MINT,
    BURN,
    CLEAR,
    ASSERT_BALANCE_EQUALS,
    ASSERT_RESERVES_EQUALS,
    ASSERT_DELTA_EQUALS,
    ASSERT_NONZERO_DELTA_COUNT_EQUALS,
    TRANSFER_FROM,
    INITIALIZE,
    DONATE,
    MODIFY_POSITION,
    SWAP,
    HARNESS_CALLBACK
}

/// @notice A router that handles an arbitrary input of actions.
/// TODO: Can continue to add functions per action.
contract ActionsRouter is IUnlockCallback, Test {
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    error ActionNotSupported();

    // error thrown so that incorrectly formatted tests don't pass silently
    error CheckParameters();

    error AssertOnExceptionNotSupported();

    IPoolManager manager;
    bytes lastReturnData;
    bool assertOnException = false;

    constructor(IPoolManager _manager) {
        manager = _manager;
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        (Actions[] memory actions, bytes[] memory params) = abi.decode(data, (Actions[], bytes[]));
        if (actions.length != params.length || actions.length == 0) revert CheckParameters();
        for (uint256 i = 0; i < actions.length; i++) {
            Actions action = actions[i];
            bytes memory param = params[i];
            if (action == Actions.SETTLE) {
                _settle();
            } else if (action == Actions.SETTLE_NATIVE) {
                _settleNative(param);
            } else if (action == Actions.SETTLE_FOR) {
                _settleFor(param);
            } else if (action == Actions.TAKE) {
                _take(param);
            } else if (action == Actions.PRANK_TAKE_FROM) {
                _prankTakeFrom(param);
            } else if (action == Actions.SYNC) {
                _sync(param);
            } else if (action == Actions.MODIFY_POSITION) {
                _modify_position(param);
            } else if (action == Actions.MINT) {
                _mint(param);
            } else if (action == Actions.BURN) {
                _burn(param);
            } else if (action == Actions.CLEAR) {
                _clear(param);
            } else if (action == Actions.ASSERT_BALANCE_EQUALS) {
                _assertBalanceEquals(param);
            } else if (action == Actions.ASSERT_RESERVES_EQUALS) {
                _assertReservesEquals(param);
            } else if (action == Actions.ASSERT_DELTA_EQUALS) {
                _assertDeltaEquals(param);
            } else if (action == Actions.ASSERT_NONZERO_DELTA_COUNT_EQUALS) {
                _assertNonzeroDeltaCountEquals(param);
            } else if (action == Actions.TRANSFER_FROM) {
                _transferFrom(param);
            } else if (action == Actions.INITIALIZE) {
                _initialize(param);
            } else if (action == Actions.DONATE) {
                _donate(param);
            } else if (action == Actions.SWAP) {
                _swap(param);
            } else if (action == Actions.HARNESS_CALLBACK) {
                _harness_callback(param);
            } else {
                assert(false); //todo: remove
                revert ActionNotSupported();
            }
            assertOnException = false;
        }
        return "";
    }

    function executeActions(Actions[] memory actions, bytes[] memory params) external payable {
        manager.unlock(abi.encode(actions, params));
    }

    /// @notice Set this to "true" to raise an assertion error if the next action reverts.
    /// This can be used to create properties that assert that specific actions must never revert,
    //  however this function should be added to fuzzing blocklists if using multi-abi mode.
    function setAssertOnException(bool value) external {
        assertOnException = value;
    }

    function _harness_callback(bytes memory params) internal {
        (address harness, bytes memory cbParams) = abi.decode(params, (address, bytes));
        IActionsHarness(harness).routerCallback(cbParams, lastReturnData);
        lastReturnData = new bytes(0); // todo: we might need some data smuggled here if harness_callback is the last item in the actions list.
    }


    function _settle() internal {
        try manager.settle() returns (uint256 paid) {
            lastReturnData = abi.encode(paid);
        } catch Error(string memory reason) {
            emit log_named_string("revert reason", reason);
            assertFalse(assertOnException, "_settle reverted, but should not have");
            revert(reason);
        }
    }

    function _settleNative(bytes memory params) internal {
        uint256 amount = abi.decode(params, (uint256));
        try manager.settle{value: amount}() returns (uint256 paid) {
            lastReturnData = abi.encode(paid);
        } catch Error(string memory reason) {
            emit log_named_string("revert reason", reason);
            assertFalse(assertOnException, "_settleNative reverted, but should not have");
            revert(reason);
        }
    }

    function _settleFor(bytes memory params) internal {
        address recipient = abi.decode(params, (address));
        try manager.settleFor(recipient) returns (uint256 paid) {
            lastReturnData = abi.encode(paid);
        } catch Error(string memory reason) {
            emit log_named_string("revert reason", reason);
            assertFalse(assertOnException, "_settleFor reverted, but should not have");
            revert(reason);
        }
    }

    function _take(bytes memory params) internal {
        (Currency currency, address recipient, int128 amount) = abi.decode(params, (Currency, address, int128));
        try manager.take(currency, recipient, uint128(amount)) {
            lastReturnData = new bytes(0);
        } catch Error(string memory reason) {
            emit log_named_string("revert reason", reason);
            assertFalse(assertOnException, "_take reverted, but should not have");
            revert(reason);
        }        
    }

    function _prankTakeFrom(bytes memory params) internal {
        if(assertOnException) {
            revert AssertOnExceptionNotSupported();
        }
        (Currency currency, address from, address recipient, uint256 amount) =
            abi.decode(params, (Currency, address, address, uint256));
        vm.prank(from);
        manager.take(currency, recipient, amount);
        lastReturnData = new bytes(0);
    }

    function _sync(bytes memory params) internal {
        Currency currency = Currency.wrap(abi.decode(params, (address)));
        try manager.sync(currency) {
            lastReturnData = new bytes(0);
        } catch Error(string memory reason) {
            emit log_named_string("revert eason", reason);
            assertFalse(assertOnException, "_sync reverted, but should not have");
        }
    }

    function _mint(bytes memory params) internal {
        (address recipient, Currency currency, uint256 amount) = abi.decode(params, (address, Currency, uint256));
        try manager.mint(recipient, currency.toId(), amount) {
            lastReturnData = new bytes(0);
        } catch Error(string memory reason) {
            emit log_named_string("revert reason", reason);
            assertFalse(assertOnException, "_mint reverted, but should not have");
            revert(reason);
        }
    }

    function _burn(bytes memory params) internal {
        (address sender, Currency currency, uint256 amount) = abi.decode(params, (address, Currency, uint256));
        try manager.burn(sender, currency.toId(), amount){ 
            lastReturnData = new bytes(0);
        } catch Error(string memory reason) {
            emit log_named_string("revert reason", reason);
            assertFalse(assertOnException, "_burn reverted, but should not have");
            revert(reason);
        }
    }

    function _clear(bytes memory params) internal {
        (Currency currency, uint256 amount, bool measureGas, string memory gasSnapName) =
            abi.decode(params, (Currency, uint256, bool, string));
        try manager.clear(currency, amount) {
            lastReturnData = new bytes(0);
            // Disable gas snapshotting b/c echidna/medusa's engines can't handle the cheatcodes.
            // if (measureGas) snapLastCall(gasSnapName);
        } catch Error(string memory reason) {
            emit log_named_string("revert reason", reason);
            assertFalse(assertOnException, "_clear reverted, but should not have");
            revert(reason);
        }
    }

    function _assertBalanceEquals(bytes memory params) internal view {
        if(assertOnException) {
            revert AssertOnExceptionNotSupported();
        }
        (Currency currency, address user, uint256 expectedBalance) = abi.decode(params, (Currency, address, uint256));
        assertEq(currency.balanceOf(user), expectedBalance, "usertoken value incorrect");
    }

    function _assertReservesEquals(bytes memory params) internal view {
        if(assertOnException) {
            revert AssertOnExceptionNotSupported();
        }
        uint256 expectedReserves = abi.decode(params, (uint256));
        assertEq(manager.getSyncedReserves(), expectedReserves, "reserves value incorrect");
    }

    function _assertDeltaEquals(bytes memory params) internal view {
        if(assertOnException) {
            revert AssertOnExceptionNotSupported();
        }
        (Currency currency, address caller, int256 expectedDelta) = abi.decode(params, (Currency, address, int256));

        assertEq(manager.currencyDelta(caller, currency), expectedDelta, "delta value incorrect");
     }

    function _assertNonzeroDeltaCountEquals(bytes memory params) internal view {
        if(assertOnException) {
            revert AssertOnExceptionNotSupported();
        }
        (uint256 expectedCount) = abi.decode(params, (uint256));
        assertEq(manager.getNonzeroDeltaCount(), expectedCount, "nonzero delta count incorrect");
    }

    function _transferFrom(bytes memory params) internal {
        if(assertOnException) {
            revert AssertOnExceptionNotSupported();
        }
        (Currency currency, address from, address recipient, uint256 amount) =
            abi.decode(params, (Currency, address, address, uint256));
        MockERC20(Currency.unwrap(currency)).transferFrom(from, recipient, uint256(amount));
        lastReturnData = new bytes(0);
    }

    function _initialize(bytes memory params) internal {
        (address token0, address token1, int24 tickSpacing, uint160 initialPrice, uint24 initialFee) = 
            abi.decode(params, (address, address, int24, uint160, uint24));

        PoolKey memory k = PoolKey(Currency.wrap(token0), Currency.wrap(token1), initialFee, tickSpacing, IHooks(address(0)));
        
        try manager.initialize(k, initialPrice, new bytes(0)) returns (int24 tick ){
            lastReturnData = abi.encode(tick);
            return;
        } catch Error(string memory reason) {
            emit log_named_string("revert reason", reason);
            assertFalse(assertOnException, "_initialize reverted, but should not have");
            revert(reason);
        }
    }

    function _donate(bytes memory params) internal {
        (PoolKey memory key, uint256 amount0, uint256 amount1) = abi.decode(params, (PoolKey, uint256, uint256));

        try manager.donate(key, amount0, amount1, new bytes(0)) returns (BalanceDelta delta) { 
            lastReturnData = abi.encode(delta);
        } catch Error(string memory reason) {
            emit log_named_string("revert reason", reason);
            assertFalse(assertOnException, "_donate reverted, but should not have");
            revert(reason);
        }
    }

    function _modify_position(bytes memory params) internal {
        (PoolKey memory key, int24 tickLower, int24 tickUpper, int128 liquidity, uint256 salt) =
            abi.decode(params, (PoolKey, int24, int24, int128, uint256));

        IPoolManager.ModifyLiquidityParams memory modLiqParams = IPoolManager.ModifyLiquidityParams(
            tickLower, 
            tickUpper, 
            liquidity, 
            bytes32(salt));

        try manager.modifyLiquidity(key, modLiqParams, new bytes(0)) returns (BalanceDelta callerDelta, BalanceDelta feesAccrued) {
            lastReturnData = abi.encode(callerDelta, feesAccrued);
        } catch Error(string memory reason) {
            emit log_named_string("revert reason", reason);
            assertFalse(assertOnException, "_modify_position reverted, but should not have");
            revert(reason);
        }

    }

    function _swap(bytes memory params) internal {
        (bool zeroForOne, int256 amount, PoolKey memory poolKey, uint160 priceLimit) = abi.decode(params, (bool, int256, PoolKey, uint160));

        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams(
            zeroForOne, 
            amount, 
            priceLimit
        );

        try manager.swap(poolKey, swapParams, new bytes(0)) returns (BalanceDelta swapDelta) {
            lastReturnData = abi.encode(swapDelta);
        } catch Error(string memory reason) {
            emit log_named_string("revert reason", reason);
            assertFalse(assertOnException, "_swap reverted, but should not have");
            revert(reason);
        }
    }

    fallback() external payable { }
    receive() external payable { }
}
