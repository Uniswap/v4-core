// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AccessLockHook, NoAccessLockHook} from "../src/test/AccessLockHook.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {PoolModifyPositionTest} from "../src/test/PoolModifyPositionTest.sol";
import {PoolSwapTest} from "../src/test/PoolSwapTest.sol";
import {PoolDonateTest} from "../src/test/PoolDonateTest.sol";
import {Constants} from "./utils/Constants.sol";
import {PoolKey} from "../src/types/PoolKey.sol";
import {Deployers} from "./utils/Deployers.sol";
import {Currency} from "../src/types/Currency.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Hooks} from "../src/libraries/Hooks.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {BalanceDelta} from "../src/types/BalanceDelta.sol";
import {PoolManager} from "../src/PoolManager.sol";

import {console2} from "forge-std/console2.sol";

contract AccessLockTest is Test, Deployers {
    AccessLockHook accessLockHook;
    NoAccessLockHook noAccessLockHook;

    function setUp() public {
        // Initialize managers and routers.
        deployFreshManagerAndRouters();
        (currency0, currency1) = deployMintAndApprove2Currencies();

        // Create AccessLockHook.
        address accessLockAddress = address(
            uint160(
                Hooks.ACCESS_LOCK_FLAG | Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG
                    | Hooks.BEFORE_MODIFY_POSITION_FLAG | Hooks.BEFORE_DONATE_FLAG
            )
        );
        deployCodeTo("AccessLockHook.sol:AccessLockHook", abi.encode(manager), accessLockAddress);
        accessLockHook = AccessLockHook(accessLockAddress);

        // Create NoAccessLockHook.
        address noAccessLockHookAddress = address(uint160(Hooks.BEFORE_MODIFY_POSITION_FLAG));
        deployCodeTo("AccessLockHook.sol:NoAccessLockHook", abi.encode(manager), noAccessLockHookAddress);
        noAccessLockHook = NoAccessLockHook(noAccessLockHookAddress);

        (key,) = initPool(
            currency0, currency1, IHooks(address(accessLockHook)), Constants.FEE_MEDIUM, SQRT_RATIO_1_1, ZERO_BYTES
        );
    }

    function test_onlyByLocker_revertsForNoAccessLockPool() public {
        (PoolKey memory keyWithoutAccessLockFlag,) =
            initPool(currency0, currency1, IHooks(noAccessLockHook), Constants.FEE_MEDIUM, SQRT_RATIO_1_1, ZERO_BYTES);

        vm.expectRevert(abi.encodeWithSelector(IPoolManager.LockedBy.selector, address(modifyPositionRouter)));
        modifyPositionRouter.modifyPosition(
            keyWithoutAccessLockFlag,
            IPoolManager.ModifyPositionParams({tickLower: 0, tickUpper: 60, liquidityDelta: 0}),
            ZERO_BYTES
        );
    }

    function test_mint_beforeModifyPosition_succeedsWithAccessLockHook() public {
        uint256 balanceOfBefore1 = MockERC20(Currency.unwrap(key.currency1)).balanceOf(address(this));
        uint256 balanceOfBefore0 = MockERC20(Currency.unwrap(key.currency0)).balanceOf(address(this));

        // Hook only takes currency 1 rn.
        uint256 hookAmountToTake1 = 2 * 10 ** 18;
        BalanceDelta delta = modifyPositionRouter.modifyPosition(
            key, IPoolManager.ModifyPositionParams(0, 60, 1 * 10 ** 18), abi.encode(hookAmountToTake1)
        );
        uint256 balanceOfAfter0 = MockERC20(Currency.unwrap(key.currency0)).balanceOf(address(this));
        uint256 balanceOfAfter1 = MockERC20(Currency.unwrap(key.currency1)).balanceOf(address(this));

        assertEq(balanceOfBefore0 - balanceOfAfter0, uint256(uint128(delta.amount0())));
        // The balance of our contract should be from the modifyPositionRouter (delta) AND the hook (hookAmountToTake1).
        assertEq(balanceOfBefore1 - balanceOfAfter1, uint256(hookAmountToTake1 + uint256(uint128(delta.amount1()))));
    }
}
