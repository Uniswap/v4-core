// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "../src/interfaces/IPoolManager.sol";
import {IHooks} from "../src/interfaces/IHooks.sol";
import {TransientStateLibrary} from "../src/libraries/TransientStateLibrary.sol";
import {Currency} from "../src/types/Currency.sol";
import {Deployers} from "./utils/Deployers.sol";
import {PoolSolvencyHandler} from "./utils/PoolSolvencyHandler.sol";
/// @notice Invariant test that a pool always stays solvent: it can always honour the positions it has
/// granted, and never holds less than it owes.
/// @dev Resolves https://github.com/Uniswap/v4-core/issues/81.
///
/// The checks deliberately avoid recomputing what the pool should owe from `LiquidityAmounts` and fee
/// growth, because a bug in the pool's math would reproduce identically in the checker and the test
/// would still pass. Instead solvency is observed against real token custody and real payouts:
///
/// - after every call, no unsettled debt survived the unlock, and the manager still holds at least the
///   protocol fees it has promised;
/// - at the end of every run, every position is actually burned. A pool that cannot pay out a position
///   it granted reverts there, and the handler can never finish holding more tokens than it started
///   with.
///
/// Scoped to a single ERC20 pool with no hooks and no claim tokens, so that the conservation check has
/// exactly one possible cause of failure. Hooks may legitimately take a cut, native currency adds value
/// plumbing, and ERC6909 claims move the liability off the token balance. Extending this to several
/// pools on the singleton manager is worthwhile follow-up work.
contract PoolSolvencyTest is Test, Deployers {
    using TransientStateLibrary for IPoolManager;

    PoolSolvencyHandler handler;

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        (key,) = initPool(currency0, currency1, IHooks(address(0)), 3000, SQRT_PRICE_1_1);

        handler = new PoolSolvencyHandler(manager, key, modifyLiquidityNoChecks, swapRouter);

        // Only the bounded entrypoints are fuzzed; `unwindAll` is reserved for `afterInvariant`.
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = PoolSolvencyHandler.addLiquidity.selector;
        selectors[1] = PoolSolvencyHandler.removeLiquidity.selector;
        selectors[2] = PoolSolvencyHandler.swapExactIn.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// @notice A completed unlock never leaves debt behind.
    /// forge-config: default.invariant.runs = 60
    /// forge-config: default.invariant.depth = 120
    /// forge-config: default.invariant.fail-on-revert = true
    /// forge-config: debug.invariant.runs = 5
    /// forge-config: debug.invariant.depth = 50
    /// forge-config: debug.invariant.fail-on-revert = true
    function invariant_noUnsettledDeltas() public view {
        assertEq(manager.getNonzeroDeltaCount(), 0, "unsettled delta outlived the unlock");
    }

    /// @notice The manager always custodies at least the protocol fees it has already promised.
    /// forge-config: default.invariant.runs = 60
    /// forge-config: default.invariant.depth = 120
    /// forge-config: default.invariant.fail-on-revert = true
    /// forge-config: debug.invariant.runs = 5
    /// forge-config: debug.invariant.depth = 50
    /// forge-config: debug.invariant.fail-on-revert = true
    function invariant_managerCoversProtocolFees() public view {
        _assertCoversProtocolFees(currency0);
        _assertCoversProtocolFees(currency1);
    }

    /// @notice Closes every position opened during the run, then checks the handler made no free money.
    /// @dev The unwind is the solvency proof: an insolvent pool reverts instead of paying out.
    function afterInvariant() public {
        handler.unwindAll();

        uint256 starting = handler.STARTING_BALANCE();
        assertLe(currency0.balanceOf(address(handler)), starting, "handler gained currency0");
        assertLe(currency1.balanceOf(address(handler)), starting, "handler gained currency1");
    }

    /// @notice Guards the invariants above: they would hold trivially if the handler never did anything.
    function test_handler_performsRealActions() public {
        handler.addLiquidity(-600, 600, 1e21);
        handler.swapExactIn(true, 1e18);
        handler.removeLiquidity(0, type(uint256).max);

        assertEq(handler.addCount(), 1, "no liquidity added");
        assertEq(handler.swapCount(), 1, "no swap executed");
        assertEq(handler.removeCount(), 1, "no liquidity removed");
        assertEq(handler.positionCount(), 1, "no position recorded");
    }

    function _assertCoversProtocolFees(Currency currency) internal view {
        assertGe(
            currency.balanceOf(address(manager)),
            manager.protocolFeesAccrued(currency),
            "manager holds less than the protocol fees it owes"
        );
    }
}
