// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {IPoolManager} from "../../src/interfaces/IPoolManager.sol";
import {FullMath} from "../../src/libraries/FullMath.sol";
import {Pool} from "../../src/libraries/Pool.sol";
import {StateLibrary} from "../../src/libraries/StateLibrary.sol";
import {TickMath} from "../../src/libraries/TickMath.sol";
import {Fuzzers} from "../../src/test/Fuzzers.sol";
import {PoolModifyLiquidityTestNoChecks} from "../../src/test/PoolModifyLiquidityTestNoChecks.sol";
import {PoolSwapTest} from "../../src/test/PoolSwapTest.sol";
import {Currency} from "../../src/types/Currency.sol";
import {PoolId} from "../../src/types/PoolId.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {ModifyLiquidityParams, SwapParams} from "../../src/types/PoolOperation.sol";
import {LiquidityAmounts} from "./LiquidityAmounts.sol";

/// @notice Invariant handler that drives a single pool with random, always-valid liquidity and swap calls.
/// @dev Every entrypoint bounds its own inputs so that no call can revert on validation. That keeps
/// `fail-on-revert = true` meaningful: a revert during a run is a real finding, not a rejected input.
/// Calls that have nothing to do (no position to burn, no budget left) return early rather than
/// `vm.assume`, so the run keeps its depth instead of being discarded.
/// Uses `PoolModifyLiquidityTestNoChecks` because `PoolModifyLiquidityTest` asserts that a liquidity
/// decrease always returns nonzero tokens, which legitimately fails for a removal that rounds to zero.
contract PoolSolvencyHandler is Fuzzers {
    using StateLibrary for IPoolManager;

    /// @notice A liquidity range this handler has opened at least once. Salt is always zero, so a
    /// range is stored once and reused, and `unwindAll` can close every range the handler created.
    struct Position {
        int24 tickLower;
        int24 tickUpper;
    }

    /// @notice Tokens minted to the handler for each currency, and the ceiling for the conservation check.
    uint256 public constant STARTING_BALANCE = 1e30;

    /// @dev Liquidity is priced for this reference amount and then scaled to the affordable budget.
    uint256 internal constant REFERENCE_LIQUIDITY = 1e18;
    /// @dev Floors that keep an action economically meaningful instead of rounding away to a no-op.
    uint128 internal constant MIN_LIQUIDITY = 1e3;
    uint256 internal constant MIN_SWAP_INPUT = 1e3;
    /// @dev A single call may spend at most this fraction of the remaining balance, so that later
    /// calls in a run still have something to trade with.
    uint256 internal constant SPEND_DIVISOR = 4;

    IPoolManager public immutable manager;
    PoolModifyLiquidityTestNoChecks public immutable modifyLiquidityRouter;
    PoolSwapTest public immutable swapRouter;

    PoolKey public key;
    PoolId internal immutable poolId;
    Currency internal immutable currency0;
    Currency internal immutable currency1;

    Position[] public positions;
    mapping(bytes32 range => bool seen) internal _known;

    /// @notice Call counters, so a unit test can prove the handler is doing real work and not no-oping.
    uint256 public addCount;
    uint256 public removeCount;
    uint256 public swapCount;

    constructor(
        IPoolManager _manager,
        PoolKey memory _key,
        PoolModifyLiquidityTestNoChecks _modifyLiquidityRouter,
        PoolSwapTest _swapRouter
    ) {
        manager = _manager;
        key = _key;
        poolId = _key.toId();
        currency0 = _key.currency0;
        currency1 = _key.currency1;
        modifyLiquidityRouter = _modifyLiquidityRouter;
        swapRouter = _swapRouter;

        _fundAndApprove(_key.currency0);
        _fundAndApprove(_key.currency1);
    }

    /// @notice Opens or tops up a liquidity position on a random, tick-spacing-aligned range.
    /// @param tickLower Unbounded lower tick.
    /// @param tickUpper Unbounded upper tick.
    /// @param liquiditySeed Unbounded seed for the liquidity to add.
    function addLiquidity(int24 tickLower, int24 tickUpper, uint256 liquiditySeed) external {
        (tickLower, tickUpper) = boundTicks(key, tickLower, tickUpper);

        uint128 maxLiquidity = _maxAddableLiquidity(tickLower, tickUpper);
        if (maxLiquidity < MIN_LIQUIDITY) return;
        uint256 liquidity = bound(liquiditySeed, MIN_LIQUIDITY, maxLiquidity);

        _modifyLiquidity(tickLower, tickUpper, int256(liquidity));
        _remember(tickLower, tickUpper);
        addCount++;
    }

    /// @notice Burns part or all of one existing position, which also collects its fees.
    /// @param positionSeed Unbounded seed selecting which open position to burn.
    /// @param liquiditySeed Unbounded seed for how much of it to burn.
    function removeLiquidity(uint256 positionSeed, uint256 liquiditySeed) external {
        if (positions.length == 0) return;

        Position memory position = positions[bound(positionSeed, 0, positions.length - 1)];
        uint128 liquidity = _liquidityOf(position);
        if (liquidity == 0) return;

        _modifyLiquidity(position.tickLower, position.tickUpper, -int256(bound(liquiditySeed, 1, liquidity)));
        removeCount++;
    }

    /// @notice Swaps an exact input amount in either direction, with no effective price limit.
    /// @param zeroForOne The swap direction.
    /// @param amountSeed Unbounded seed for the input amount.
    function swapExactIn(bool zeroForOne, uint256 amountSeed) external {
        // Without active liquidity there is nothing to swap against.
        if (manager.getLiquidity(poolId) == 0) return;

        uint256 spendable = (zeroForOne ? currency0 : currency1).balanceOf(address(this)) / SPEND_DIVISOR;
        if (spendable < MIN_SWAP_INPUT) return;

        swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(bound(amountSeed, MIN_SWAP_INPUT, spendable)),
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
        swapCount++;
    }

    /// @notice Closes every position the handler ever opened.
    /// @dev This is the solvency proof, and is deliberately not a fuzz target: it is called once from
    /// `afterInvariant`. Rather than recomputing what the pool owes -- which would just mirror any bug
    /// in the pool's own math -- it asks the pool to actually pay out. If the pool granted liquidity it
    /// cannot honour, the payout reverts here.
    function unwindAll() external {
        uint256 length = positions.length;
        for (uint256 i = 0; i < length; i++) {
            Position memory position = positions[i];
            uint128 liquidity = _liquidityOf(position);
            if (liquidity == 0) continue;
            _modifyLiquidity(position.tickLower, position.tickUpper, -int256(uint256(liquidity)));
        }
    }

    /// @notice The number of distinct ranges the handler has opened.
    function positionCount() external view returns (uint256) {
        return positions.length;
    }

    function _modifyLiquidity(int24 tickLower, int24 tickUpper, int256 liquidityDelta) internal {
        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: liquidityDelta, salt: bytes32(0)
            }),
            ""
        );
    }

    /// @dev The largest liquidity that can be added to this range right now: the lower of what the two
    /// ticks still have room for and what the handler can still pay for.
    function _maxAddableLiquidity(int24 tickLower, int24 tickUpper) internal view returns (uint128) {
        // Liquidity accumulates per tick across positions, so cap by live headroom rather than by the
        // per-tick maximum, which a single position would otherwise be allowed to reach on its own.
        (uint128 grossLower,) = manager.getTickLiquidity(poolId, tickLower);
        (uint128 grossUpper,) = manager.getTickLiquidity(poolId, tickUpper);
        uint128 gross = grossLower > grossUpper ? grossLower : grossUpper;

        uint128 maxPerTick = Pool.tickSpacingToMaxLiquidityPerTick(key.tickSpacing);
        if (gross >= maxPerTick) return 0;
        // Headroom fits uint128 by construction, which keeps the affordability cap below in range too.
        uint256 maxLiquidity = maxPerTick - gross;

        (uint160 sqrtPriceX96,,,) = manager.getSlot0(poolId);
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            uint128(REFERENCE_LIQUIDITY)
        );

        uint256 affordable = _affordableLiquidity(currency0, amount0);
        uint256 affordable1 = _affordableLiquidity(currency1, amount1);
        if (affordable1 < affordable) affordable = affordable1;

        return uint128(affordable < maxLiquidity ? affordable : maxLiquidity);
    }

    /// @dev Scales `REFERENCE_LIQUIDITY` by the budget available for one currency. Pricing a fixed
    /// reference amount and scaling avoids the uint128 overflow that deriving liquidity directly from a
    /// large budget hits on narrow or extreme ranges.
    function _affordableLiquidity(Currency currency, uint256 referenceCost) internal view returns (uint256) {
        // A range entirely on one side of the current price needs none of this currency.
        if (referenceCost == 0) return type(uint256).max;
        return FullMath.mulDiv(REFERENCE_LIQUIDITY, currency.balanceOf(address(this)) / SPEND_DIVISOR, referenceCost);
    }

    function _liquidityOf(Position memory position) internal view returns (uint128 liquidity) {
        (liquidity,,) = manager.getPositionInfo(
            poolId, address(modifyLiquidityRouter), position.tickLower, position.tickUpper, bytes32(0)
        );
    }

    function _remember(int24 tickLower, int24 tickUpper) internal {
        bytes32 range = keccak256(abi.encode(tickLower, tickUpper));
        if (_known[range]) return;
        _known[range] = true;
        positions.push(Position({tickLower: tickLower, tickUpper: tickUpper}));
    }

    function _fundAndApprove(Currency currency) internal {
        MockERC20 token = MockERC20(Currency.unwrap(currency));
        token.mint(address(this), STARTING_BALANCE);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);
        token.approve(address(swapRouter), type(uint256).max);
    }
}
