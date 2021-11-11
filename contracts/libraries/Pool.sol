// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.9;

import {IPoolEvents} from '../interfaces/pool/IPoolEvents.sol';

import {SafeCast} from './SafeCast.sol';
import {Tick} from './Tick.sol';
import {TickBitmap} from './TickBitmap.sol';
import {Position} from './Position.sol';
import {Oracle} from './Oracle.sol';
import {FullMath} from './FullMath.sol';
import {FixedPoint128} from './FixedPoint128.sol';
import {TransferHelper} from './TransferHelper.sol';
import {TickMath} from './TickMath.sol';
import {SqrtPriceMath} from './SqrtPriceMath.sol';
import {SwapMath} from './SwapMath.sol';
import {LowGasERC20} from './LowGasERC20.sol';

import {IERC20Minimal} from '../interfaces/external/IERC20Minimal.sol';
import {IMintCallback} from '../interfaces/callback/IMintCallback.sol';
import {ISwapCallback} from '../interfaces/callback/ISwapCallback.sol';
import {IFlashCallback} from '../interfaces/callback/IFlashCallback.sol';

library Pool {
    using SafeCast for *;
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;
    using Oracle for Oracle.Observation[65535];

    /// @notice Emitted exactly once by a pool when #initialize is first called on the pool
    /// @dev Mint/Burn/Swap cannot be emitted by the pool before Initialize
    /// @param sqrtPriceX96 The initial sqrt price of the pool, as a Q64.96
    /// @param tick The initial tick of the pool, i.e. log base 1.0001 of the starting price of the pool
    event Initialize(uint160 sqrtPriceX96, int24 tick);

    /// @notice Emitted when liquidity is minted for a given position
    /// @param sender The address that minted the liquidity
    /// @param owner The owner of the position and recipient of any minted liquidity
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param amount The amount of liquidity minted to the position range
    /// @param amount0 How much token0 was required for the minted liquidity
    /// @param amount1 How much token1 was required for the minted liquidity
    event Mint(
        address sender,
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice Emitted when fees are collected by the owner of a position
    /// @dev Collect events may be emitted with zero amount0 and amount1 when the caller chooses not to collect fees
    /// @param owner The owner of the position for which fees are collected
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param amount0 The amount of token0 fees collected
    /// @param amount1 The amount of token1 fees collected
    event Collect(
        address indexed owner,
        address recipient,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount0,
        uint128 amount1
    );

    /// @notice Emitted when a position's liquidity is removed
    /// @dev Does not withdraw any fees earned by the liquidity position, which must be withdrawn via #collect
    /// @param owner The owner of the position for which liquidity is removed
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param amount The amount of liquidity to remove
    /// @param amount0 The amount of token0 withdrawn
    /// @param amount1 The amount of token1 withdrawn
    event Burn(
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice Emitted by the pool for any swaps between token0 and token1
    /// @param sender The address that initiated the swap call, and that received the callback
    /// @param recipient The address that received the output of the swap
    /// @param amount0 The delta of the token0 balance of the pool
    /// @param amount1 The delta of the token1 balance of the pool
    /// @param sqrtPriceX96 The sqrt(price) of the pool after the swap, as a Q64.96
    /// @param liquidity The liquidity of the pool after the swap
    /// @param tick The log base 1.0001 of price of the pool after the swap
    event Swap(
        address indexed sender,
        address indexed recipient,
        int256 amount0,
        int256 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );

    /// @notice Emitted by the pool for any flashes of token0/token1
    /// @param sender The address that initiated the swap call, and that received the callback
    /// @param recipient The address that received the tokens from flash
    /// @param amount0 The amount of token0 that was flashed
    /// @param amount1 The amount of token1 that was flashed
    /// @param paid0 The amount of token0 paid for the flash, which can exceed the amount0 plus the fee
    /// @param paid1 The amount of token1 paid for the flash, which can exceed the amount1 plus the fee
    event Flash(
        address indexed sender,
        address indexed recipient,
        uint256 amount0,
        uint256 amount1,
        uint256 paid0,
        uint256 paid1
    );

    /// @notice Emitted by the pool for increases to the number of observations that can be stored
    /// @dev observationCardinalityNext is not the observation cardinality until an observation is written at the index
    /// just before a mint/swap/burn.
    /// @param observationCardinalityNextOld The previous value of the next observation cardinality
    /// @param observationCardinalityNextNew The updated value of the next observation cardinality
    event IncreaseObservationCardinalityNext(
        uint16 observationCardinalityNextOld,
        uint16 observationCardinalityNextNew
    );

    /// @notice Emitted when the protocol fee is changed by the pool
    /// @param feeProtocol0Old The previous value of the token0 protocol fee
    /// @param feeProtocol1Old The previous value of the token1 protocol fee
    /// @param feeProtocol0New The updated value of the token0 protocol fee
    /// @param feeProtocol1New The updated value of the token1 protocol fee
    event SetFeeProtocol(uint8 feeProtocol0Old, uint8 feeProtocol1Old, uint8 feeProtocol0New, uint8 feeProtocol1New);

    /// @notice Emitted when the collected protocol fees are withdrawn by the factory owner
    /// @param sender The address that collects the protocol fees
    /// @param recipient The address that receives the collected protocol fees
    /// @param amount0 The amount of token0 protocol fees that is withdrawn
    /// @param amount0 The amount of token1 protocol fees that is withdrawn
    event CollectProtocol(address indexed sender, address indexed recipient, uint128 amount0, uint128 amount1);

    /// @notice Returns the key for identifying a pool
    struct Key {
        /// @notice The lower token of the pool, sorted numerically
        address token0;
        /// @notice The higher token of the pool, sorted numerically
        address token1;
        /// @notice The fee for the pool
        uint24 fee;
    }

    /// @notice Configuration associated with a given fee tier
    struct FeeConfiguration {
        /// @notice Initialized tick must be a multiple of this number
        int24 tickSpacing;
        /// @notice The maximum amount of position liquidity that can use any tick in the range
        uint128 maxLiquidityPerTick;
    }

    struct Slot0 {
        // the current price
        uint160 sqrtPriceX96;
        // the current tick
        int24 tick;
        // the most-recently updated index of the observations array
        uint16 observationIndex;
        // the current maximum number of observations that are being stored
        uint16 observationCardinality;
        // the next maximum number of observations to store, triggered in observations.write
        uint16 observationCardinalityNext;
        // the current protocol fee as a percentage of the swap fee taken on withdrawal
        // represented as an integer denominator (1/x)%
        uint8 feeProtocol;
        // whether the pool is locked
        bool unlocked;
    }

    // accumulated protocol fees in token0/token1 units
    // todo: this might be better accumulated in a pool
    struct ProtocolFees {
        uint128 token0;
        uint128 token1;
    }

    /// @dev The state of a pool
    struct State {
        Slot0 slot0;
        uint256 feeGrowthGlobal0X128;
        uint256 feeGrowthGlobal1X128;
        ProtocolFees protocolFees;
        uint128 liquidity;
        mapping(int24 => Tick.Info) ticks;
        mapping(int16 => uint256) tickBitmap;
        mapping(bytes32 => Position.Info) positions;
        Oracle.Observation[65535] observations;
    }

    /// @dev Locks the pool to perform some action on it while protected from reentrancy
    modifier lock(State storage self) {
        require(self.slot0.unlocked, 'LOK');
        self.slot0.unlocked = false;
        _;
        self.slot0.unlocked = true;
    }

    /// @dev Common checks for valid tick inputs.
    function checkTicks(int24 tickLower, int24 tickUpper) internal pure {
        require(tickLower < tickUpper, 'TLU');
        require(tickLower >= TickMath.MIN_TICK, 'TLM');
        require(tickUpper <= TickMath.MAX_TICK, 'TUM');
    }

    function snapshotCumulativesInside(
        State storage self,
        int24 tickLower,
        int24 tickUpper,
        uint32 time
    )
        internal
        view
        returns (
            int56 tickCumulativeInside,
            uint160 secondsPerLiquidityInsideX128,
            uint32 secondsInside
        )
    {
        checkTicks(tickLower, tickUpper);

        int56 tickCumulativeLower;
        int56 tickCumulativeUpper;
        uint160 secondsPerLiquidityOutsideLowerX128;
        uint160 secondsPerLiquidityOutsideUpperX128;
        uint32 secondsOutsideLower;
        uint32 secondsOutsideUpper;

        {
            Tick.Info storage lower = self.ticks[tickLower];
            Tick.Info storage upper = self.ticks[tickUpper];
            bool initializedLower;
            (tickCumulativeLower, secondsPerLiquidityOutsideLowerX128, secondsOutsideLower, initializedLower) = (
                lower.tickCumulativeOutside,
                lower.secondsPerLiquidityOutsideX128,
                lower.secondsOutside,
                lower.initialized
            );
            require(initializedLower);

            bool initializedUpper;
            (tickCumulativeUpper, secondsPerLiquidityOutsideUpperX128, secondsOutsideUpper, initializedUpper) = (
                upper.tickCumulativeOutside,
                upper.secondsPerLiquidityOutsideX128,
                upper.secondsOutside,
                upper.initialized
            );
            require(initializedUpper);
        }

        Slot0 memory _slot0 = self.slot0;

        unchecked {
            if (_slot0.tick < tickLower) {
                return (
                    tickCumulativeLower - tickCumulativeUpper,
                    secondsPerLiquidityOutsideLowerX128 - secondsPerLiquidityOutsideUpperX128,
                    secondsOutsideLower - secondsOutsideUpper
                );
            } else if (_slot0.tick < tickUpper) {
                (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = self.observations.observeSingle(
                    time,
                    0,
                    _slot0.tick,
                    _slot0.observationIndex,
                    self.liquidity,
                    _slot0.observationCardinality
                );
                return (
                    tickCumulative - tickCumulativeLower - tickCumulativeUpper,
                    secondsPerLiquidityCumulativeX128 -
                        secondsPerLiquidityOutsideLowerX128 -
                        secondsPerLiquidityOutsideUpperX128,
                    time - secondsOutsideLower - secondsOutsideUpper
                );
            } else {
                return (
                    tickCumulativeUpper - tickCumulativeLower,
                    secondsPerLiquidityOutsideUpperX128 - secondsPerLiquidityOutsideLowerX128,
                    secondsOutsideUpper - secondsOutsideLower
                );
            }
        }
    }

    function observe(
        State storage self,
        uint32 time,
        uint32[] calldata secondsAgos
    ) internal view returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) {
        return
            self.observations.observe(
                time,
                secondsAgos,
                self.slot0.tick,
                self.slot0.observationIndex,
                self.liquidity,
                self.slot0.observationCardinality
            );
    }

    function increaseObservationCardinalityNext(State storage self, uint16 observationCardinalityNext)
        internal
        lock(self)
    {
        uint16 observationCardinalityNextOld = self.slot0.observationCardinalityNext; // for the event
        uint16 observationCardinalityNextNew = self.observations.grow(
            observationCardinalityNextOld,
            observationCardinalityNext
        );
        self.slot0.observationCardinalityNext = observationCardinalityNextNew;
        if (observationCardinalityNextOld != observationCardinalityNextNew)
            emit IncreaseObservationCardinalityNext(observationCardinalityNextOld, observationCardinalityNextNew);
    }

    /// @dev not locked because it initializes unlocked
    function initialize(
        State storage self,
        uint32 time,
        uint160 sqrtPriceX96
    ) internal {
        require(self.slot0.sqrtPriceX96 == 0, 'AI');

        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        (uint16 cardinality, uint16 cardinalityNext) = self.observations.initialize(time);

        self.slot0 = Slot0({
            sqrtPriceX96: sqrtPriceX96,
            tick: tick,
            observationIndex: 0,
            observationCardinality: cardinality,
            observationCardinalityNext: cardinalityNext,
            feeProtocol: 0,
            unlocked: true
        });

        emit Initialize(sqrtPriceX96, tick);
    }

    struct ModifyPositionParams {
        // the address that owns the position
        address owner;
        // the lower and upper tick of the position
        int24 tickLower;
        int24 tickUpper;
        // any change in liquidity
        int128 liquidityDelta;
    }

    /// @dev Effect some changes to a position
    /// @param params the position details and the change to the position's liquidity to effect
    /// @return position a storage pointer referencing the position with the given owner and tick range
    /// @return amount0 the amount of token0 owed to the pool, negative if the pool should pay the recipient
    /// @return amount1 the amount of token1 owed to the pool, negative if the pool should pay the recipient
    function _modifyPosition(
        State storage self,
        FeeConfiguration memory config,
        ModifyPositionParams memory params,
        uint32 time
    )
        private
        returns (
            Position.Info storage position,
            int256 amount0,
            int256 amount1
        )
    {
        checkTicks(params.tickLower, params.tickUpper);

        Slot0 memory _slot0 = self.slot0; // SLOAD for gas optimization

        position = _updatePosition(
            self,
            config,
            params.owner,
            params.tickLower,
            params.tickUpper,
            params.liquidityDelta,
            _slot0.tick,
            time
        );

        if (params.liquidityDelta != 0) {
            if (_slot0.tick < params.tickLower) {
                // current tick is below the passed range; liquidity can only become in range by crossing from left to
                // right, when we'll need _more_ token0 (it's becoming more valuable) so user must provide it
                amount0 = SqrtPriceMath.getAmount0Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
            } else if (_slot0.tick < params.tickUpper) {
                // current tick is inside the passed range
                uint128 liquidityBefore = self.liquidity; // SLOAD for gas optimization

                // write an oracle entry
                (self.slot0.observationIndex, self.slot0.observationCardinality) = self.observations.write(
                    _slot0.observationIndex,
                    time,
                    _slot0.tick,
                    liquidityBefore,
                    _slot0.observationCardinality,
                    _slot0.observationCardinalityNext
                );

                amount0 = SqrtPriceMath.getAmount0Delta(
                    _slot0.sqrtPriceX96,
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    _slot0.sqrtPriceX96,
                    params.liquidityDelta
                );

                self.liquidity = params.liquidityDelta < 0
                    ? liquidityBefore - uint128(-params.liquidityDelta)
                    : liquidityBefore + uint128(params.liquidityDelta);
            } else {
                // current tick is above the passed range; liquidity can only become in range by crossing from right to
                // left, when we'll need _more_ token1 (it's becoming more valuable) so user must provide it
                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
            }
        }
    }

    /// @dev Gets and updates a position with the given liquidity delta
    /// @param owner the owner of the position
    /// @param tickLower the lower tick of the position's tick range
    /// @param tickUpper the upper tick of the position's tick range
    /// @param tick the current tick, passed to avoid sloads
    function _updatePosition(
        State storage self,
        FeeConfiguration memory config,
        address owner,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta,
        int24 tick,
        uint32 time
    ) internal returns (Position.Info storage position) {
        unchecked {
            position = self.positions.get(owner, tickLower, tickUpper);

            uint256 _feeGrowthGlobal0X128 = self.feeGrowthGlobal0X128; // SLOAD for gas optimization
            uint256 _feeGrowthGlobal1X128 = self.feeGrowthGlobal1X128; // SLOAD for gas optimization

            // if we need to update the ticks, do it
            bool flippedLower;
            bool flippedUpper;
            if (liquidityDelta != 0) {
                (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = self.observations.observeSingle(
                    time,
                    0,
                    self.slot0.tick,
                    self.slot0.observationIndex,
                    self.liquidity,
                    self.slot0.observationCardinality
                );

                flippedLower = self.ticks.update(
                    tickLower,
                    tick,
                    liquidityDelta,
                    _feeGrowthGlobal0X128,
                    _feeGrowthGlobal1X128,
                    secondsPerLiquidityCumulativeX128,
                    tickCumulative,
                    time,
                    false,
                    config.maxLiquidityPerTick
                );
                flippedUpper = self.ticks.update(
                    tickUpper,
                    tick,
                    liquidityDelta,
                    _feeGrowthGlobal0X128,
                    _feeGrowthGlobal1X128,
                    secondsPerLiquidityCumulativeX128,
                    tickCumulative,
                    time,
                    true,
                    config.maxLiquidityPerTick
                );

                if (flippedLower) {
                    self.tickBitmap.flipTick(tickLower, config.tickSpacing);
                }
                if (flippedUpper) {
                    self.tickBitmap.flipTick(tickUpper, config.tickSpacing);
                }
            }

            (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = self.ticks.getFeeGrowthInside(
                tickLower,
                tickUpper,
                tick,
                _feeGrowthGlobal0X128,
                _feeGrowthGlobal1X128
            );

            position.update(liquidityDelta, feeGrowthInside0X128, feeGrowthInside1X128);

            // clear any tick data that is no longer needed
            if (liquidityDelta < 0) {
                if (flippedLower) {
                    self.ticks.clear(tickLower);
                }
                if (flippedUpper) {
                    self.ticks.clear(tickUpper);
                }
            }
        }
    }

    function mint(
        State storage self,
        FeeConfiguration memory config,
        Key memory key,
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        uint32 time,
        bytes calldata data
    ) internal lock(self) returns (uint256 amount0, uint256 amount1) {
        require(amount > 0);
        (, int256 amount0Int, int256 amount1Int) = _modifyPosition(
            self,
            config,
            ModifyPositionParams({
                owner: recipient,
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: int256(uint256(amount)).toInt128()
            }),
            time
        );

        amount0 = uint256(amount0Int);
        amount1 = uint256(amount1Int);

        uint256 balance0Before;
        uint256 balance1Before;
        if (amount0 > 0) balance0Before = LowGasERC20.balance(key.token0);
        if (amount1 > 0) balance1Before = LowGasERC20.balance(key.token1);
        IMintCallback(msg.sender).mintCallback(amount0, amount1, data);
        if (amount0 > 0) require(balance0Before + amount0 <= LowGasERC20.balance(key.token0), 'M0');
        if (amount1 > 0) require(balance1Before + amount1 <= LowGasERC20.balance(key.token1), 'M1');

        emit Mint(msg.sender, recipient, tickLower, tickUpper, amount, amount0, amount1);
    }

    function collect(
        State storage self,
        Key memory key,
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) internal lock(self) returns (uint128 amount0, uint128 amount1) {
        unchecked {
            // we don't need to checkTicks here, because invalid positions will never have non-zero tokensOwed{0,1}
            Position.Info storage position = self.positions.get(msg.sender, tickLower, tickUpper);

            amount0 = amount0Requested > position.tokensOwed0 ? position.tokensOwed0 : amount0Requested;
            amount1 = amount1Requested > position.tokensOwed1 ? position.tokensOwed1 : amount1Requested;

            if (amount0 > 0) {
                position.tokensOwed0 -= amount0;
                TransferHelper.safeTransfer(key.token0, recipient, amount0);
            }
            if (amount1 > 0) {
                position.tokensOwed1 -= amount1;
                TransferHelper.safeTransfer(key.token1, recipient, amount1);
            }

            emit Collect(msg.sender, recipient, tickLower, tickUpper, amount0, amount1);
        }
    }

    function burn(
        State storage self,
        FeeConfiguration memory config,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        uint32 time
    ) internal lock(self) returns (uint256 amount0, uint256 amount1) {
        unchecked {
            (Position.Info storage position, int256 amount0Int, int256 amount1Int) = _modifyPosition(
                self,
                config,
                ModifyPositionParams({
                    owner: msg.sender,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidityDelta: -int256(uint256(amount)).toInt128()
                }),
                time
            );

            amount0 = uint256(-amount0Int);
            amount1 = uint256(-amount1Int);

            if (amount0 > 0 || amount1 > 0) {
                (position.tokensOwed0, position.tokensOwed1) = (
                    position.tokensOwed0 + uint128(amount0),
                    position.tokensOwed1 + uint128(amount1)
                );
            }

            emit Burn(msg.sender, tickLower, tickUpper, amount, amount0, amount1);
        }
    }

    struct SwapCache {
        // the protocol fee for the input token
        uint8 feeProtocol;
        // liquidity at the beginning of the swap
        uint128 liquidityStart;
        // the current value of the tick accumulator, computed only if we cross an initialized tick
        int56 tickCumulative;
        // the current value of seconds per liquidity accumulator, computed only if we cross an initialized tick
        uint160 secondsPerLiquidityCumulativeX128;
        // whether we've computed and cached the above two accumulators
        bool computedLatestObservation;
    }

    // the top level state of the swap, the results of which are recorded in storage at the end
    struct SwapState {
        // the amount remaining to be swapped in/out of the input/output asset
        int256 amountSpecifiedRemaining;
        // the amount already swapped out/in of the output/input asset
        int256 amountCalculated;
        // current sqrt(price)
        uint160 sqrtPriceX96;
        // the tick associated with the current price
        int24 tick;
        // the global fee growth of the input token
        uint256 feeGrowthGlobalX128;
        // amount of input token paid as protocol fee
        uint128 protocolFee;
        // the current liquidity in range
        uint128 liquidity;
    }

    struct StepComputations {
        // the price at the beginning of the step
        uint160 sqrtPriceStartX96;
        // the next tick to swap to from the current tick in the swap direction
        int24 tickNext;
        // whether tickNext is initialized or not
        bool initialized;
        // sqrt(price) for the next tick (1/0)
        uint160 sqrtPriceNextX96;
        // how much is being swapped in in this step
        uint256 amountIn;
        // how much is being swapped out
        uint256 amountOut;
        // how much fee is being paid in
        uint256 feeAmount;
    }

    function swap(
        State storage self,
        Key memory key,
        FeeConfiguration memory config,
        uint32 time,
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) internal returns (int256 amount0, int256 amount1) {
        require(amountSpecified != 0, 'AS');

        Slot0 memory slot0Start = self.slot0;

        require(slot0Start.unlocked, 'LOK');
        require(
            zeroForOne
                ? sqrtPriceLimitX96 < slot0Start.sqrtPriceX96 && sqrtPriceLimitX96 > TickMath.MIN_SQRT_RATIO
                : sqrtPriceLimitX96 > slot0Start.sqrtPriceX96 && sqrtPriceLimitX96 < TickMath.MAX_SQRT_RATIO,
            'SPL'
        );

        self.slot0.unlocked = false;

        SwapCache memory cache = SwapCache({
            liquidityStart: self.liquidity,
            feeProtocol: zeroForOne ? (slot0Start.feeProtocol % 16) : (slot0Start.feeProtocol >> 4),
            secondsPerLiquidityCumulativeX128: 0,
            tickCumulative: 0,
            computedLatestObservation: false
        });

        bool exactInput = amountSpecified > 0;

        SwapState memory state = SwapState({
            amountSpecifiedRemaining: amountSpecified,
            amountCalculated: 0,
            sqrtPriceX96: slot0Start.sqrtPriceX96,
            tick: slot0Start.tick,
            feeGrowthGlobalX128: zeroForOne ? self.feeGrowthGlobal0X128 : self.feeGrowthGlobal1X128,
            protocolFee: 0,
            liquidity: cache.liquidityStart
        });

        // continue swapping as long as we haven't used the entire input/output and haven't reached the price limit
        while (state.amountSpecifiedRemaining != 0 && state.sqrtPriceX96 != sqrtPriceLimitX96) {
            StepComputations memory step;

            step.sqrtPriceStartX96 = state.sqrtPriceX96;

            (step.tickNext, step.initialized) = self.tickBitmap.nextInitializedTickWithinOneWord(
                state.tick,
                config.tickSpacing,
                zeroForOne
            );

            // ensure that we do not overshoot the min/max tick, as the tick bitmap is not aware of these bounds
            if (step.tickNext < TickMath.MIN_TICK) {
                step.tickNext = TickMath.MIN_TICK;
            } else if (step.tickNext > TickMath.MAX_TICK) {
                step.tickNext = TickMath.MAX_TICK;
            }

            // get the price for the next tick
            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.tickNext);

            // compute values to swap to the target tick, price limit, or point where input/output amount is exhausted
            (state.sqrtPriceX96, step.amountIn, step.amountOut, step.feeAmount) = SwapMath.computeSwapStep(
                state.sqrtPriceX96,
                (zeroForOne ? step.sqrtPriceNextX96 < sqrtPriceLimitX96 : step.sqrtPriceNextX96 > sqrtPriceLimitX96)
                    ? sqrtPriceLimitX96
                    : step.sqrtPriceNextX96,
                state.liquidity,
                state.amountSpecifiedRemaining,
                key.fee
            );

            if (exactInput) {
                // safe because we test that amountSpecified > amountIn + feeAmount in SwapMath
                unchecked {
                    state.amountSpecifiedRemaining -= (step.amountIn + step.feeAmount).toInt256();
                }
                state.amountCalculated = state.amountCalculated - step.amountOut.toInt256();
            } else {
                unchecked {
                    state.amountSpecifiedRemaining += step.amountOut.toInt256();
                }
                state.amountCalculated = state.amountCalculated + (step.amountIn + step.feeAmount).toInt256();
            }

            // if the protocol fee is on, calculate how much is owed, decrement feeAmount, and increment protocolFee
            if (cache.feeProtocol > 0) {
                unchecked {
                    uint256 delta = step.feeAmount / cache.feeProtocol;
                    step.feeAmount -= delta;
                    state.protocolFee += uint128(delta);
                }
            }

            // update global fee tracker
            if (state.liquidity > 0) {
                unchecked {
                    state.feeGrowthGlobalX128 += FullMath.mulDiv(step.feeAmount, FixedPoint128.Q128, state.liquidity);
                }
            }

            // shift tick if we reached the next price
            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                // if the tick is initialized, run the tick transition
                if (step.initialized) {
                    // check for the placeholder value, which we replace with the actual value the first time the swap
                    // crosses an initialized tick
                    if (!cache.computedLatestObservation) {
                        (cache.tickCumulative, cache.secondsPerLiquidityCumulativeX128) = self
                            .observations
                            .observeSingle(
                                time,
                                0,
                                slot0Start.tick,
                                slot0Start.observationIndex,
                                cache.liquidityStart,
                                slot0Start.observationCardinality
                            );
                        cache.computedLatestObservation = true;
                    }
                    int128 liquidityNet = self.ticks.cross(
                        step.tickNext,
                        (zeroForOne ? state.feeGrowthGlobalX128 : self.feeGrowthGlobal0X128),
                        (zeroForOne ? self.feeGrowthGlobal1X128 : state.feeGrowthGlobalX128),
                        cache.secondsPerLiquidityCumulativeX128,
                        cache.tickCumulative,
                        time
                    );
                    // if we're moving leftward, we interpret liquidityNet as the opposite sign
                    // safe because liquidityNet cannot be type(int128).min
                    unchecked {
                        if (zeroForOne) liquidityNet = -liquidityNet;
                    }

                    state.liquidity = liquidityNet < 0
                        ? state.liquidity - uint128(-liquidityNet)
                        : state.liquidity + uint128(liquidityNet);
                }

                unchecked {
                    state.tick = zeroForOne ? step.tickNext - 1 : step.tickNext;
                }
            } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
                // recompute unless we're on a lower tick boundary (i.e. already transitioned ticks), and haven't moved
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
            }
        }

        // update tick and write an oracle entry if the tick change
        if (state.tick != slot0Start.tick) {
            (uint16 observationIndex, uint16 observationCardinality) = self.observations.write(
                slot0Start.observationIndex,
                time,
                slot0Start.tick,
                cache.liquidityStart,
                slot0Start.observationCardinality,
                slot0Start.observationCardinalityNext
            );
            (
                self.slot0.sqrtPriceX96,
                self.slot0.tick,
                self.slot0.observationIndex,
                self.slot0.observationCardinality
            ) = (state.sqrtPriceX96, state.tick, observationIndex, observationCardinality);
        } else {
            // otherwise just update the price
            self.slot0.sqrtPriceX96 = state.sqrtPriceX96;
        }

        // update liquidity if it changed
        if (cache.liquidityStart != state.liquidity) self.liquidity = state.liquidity;

        // update fee growth global and, if necessary, protocol fees
        // overflow is acceptable, protocol has to withdraw before it hits type(uint128).max fees
        if (zeroForOne) {
            self.feeGrowthGlobal0X128 = state.feeGrowthGlobalX128;
            unchecked {
                if (state.protocolFee > 0) self.protocolFees.token0 += state.protocolFee;
            }
        } else {
            self.feeGrowthGlobal1X128 = state.feeGrowthGlobalX128;
            unchecked {
                if (state.protocolFee > 0) self.protocolFees.token1 += state.protocolFee;
            }
        }

        unchecked {
            (amount0, amount1) = zeroForOne == exactInput
                ? (amountSpecified - state.amountSpecifiedRemaining, state.amountCalculated)
                : (state.amountCalculated, amountSpecified - state.amountSpecifiedRemaining);
        }

        // do the transfers and collect payment
        if (zeroForOne) {
            unchecked {
                if (amount1 < 0) TransferHelper.safeTransfer(key.token1, recipient, uint256(-amount1));
            }

            uint256 balance0Before = LowGasERC20.balance(key.token0);
            ISwapCallback(msg.sender).swapCallback(amount0, amount1, data);
            require(balance0Before + uint256(amount0) <= LowGasERC20.balance(key.token0), 'IIA');
        } else {
            unchecked {
                if (amount0 < 0) TransferHelper.safeTransfer(key.token0, recipient, uint256(-amount0));
            }

            uint256 balance1Before = LowGasERC20.balance(key.token1);
            ISwapCallback(msg.sender).swapCallback(amount0, amount1, data);
            require(balance1Before + uint256(amount1) <= LowGasERC20.balance(key.token1), 'IIA');
        }

        emit Swap(msg.sender, recipient, amount0, amount1, state.sqrtPriceX96, state.liquidity, state.tick);
        self.slot0.unlocked = true;
    }

    function setFeeProtocol(
        State storage self,
        uint8 feeProtocol0,
        uint8 feeProtocol1
    ) internal lock(self) {
        require(
            (feeProtocol0 == 0 || (feeProtocol0 >= 4 && feeProtocol0 <= 10)) &&
                (feeProtocol1 == 0 || (feeProtocol1 >= 4 && feeProtocol1 <= 10))
        );
        uint8 feeProtocolOld = self.slot0.feeProtocol;
        self.slot0.feeProtocol = feeProtocol0 + (feeProtocol1 << 4);
        emit SetFeeProtocol(feeProtocolOld % 16, feeProtocolOld >> 4, feeProtocol0, feeProtocol1);
    }

    function collectProtocol(
        State storage self,
        Key memory key,
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) internal lock(self) returns (uint128 amount0, uint128 amount1) {
        unchecked {
            amount0 = amount0Requested > self.protocolFees.token0 ? self.protocolFees.token0 : amount0Requested;
            amount1 = amount1Requested > self.protocolFees.token1 ? self.protocolFees.token1 : amount1Requested;

            if (amount0 > 0) {
                if (amount0 == self.protocolFees.token0) amount0--; // ensure that the slot is not cleared, for gas savings
                self.protocolFees.token0 -= amount0;
                TransferHelper.safeTransfer(key.token0, recipient, amount0);
            }
            if (amount1 > 0) {
                if (amount1 == self.protocolFees.token1) amount1--; // ensure that the slot is not cleared, for gas savings
                self.protocolFees.token1 -= amount1;
                TransferHelper.safeTransfer(key.token1, recipient, amount1);
            }

            emit CollectProtocol(msg.sender, recipient, amount0, amount1);
        }
    }
}
