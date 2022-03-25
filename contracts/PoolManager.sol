// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Hooks} from './libraries/Hooks.sol';
import {Pool} from './libraries/Pool.sol';
import {Tick} from './libraries/Tick.sol';
import {SafeCast} from './libraries/SafeCast.sol';
import {TWAMM} from './libraries/TWAMM/TWAMM.sol';

import {IERC20Minimal} from './interfaces/external/IERC20Minimal.sol';
import {NoDelegateCall} from './NoDelegateCall.sol';
import {IHooks} from './interfaces/IHooks.sol';
import {IPoolManager} from './interfaces/IPoolManager.sol';
import {ILockCallback} from './interfaces/callback/ILockCallback.sol';

/// @notice Holds the state for all pools
contract PoolManager is IPoolManager, NoDelegateCall {
    using TWAMM for TWAMM.State;
    using SafeCast for *;
    using Pool for *;
    using Hooks for IHooks;

    mapping(bytes32 => Pool.State) internal pools; // TODO: Private rn because public disallows nested mappings

    function slot0(bytes32 poolId) public view returns (Pool.Slot0 memory) {
        return pools[poolId].slot0;
    }

    /// @dev For mocking in unit tests
    function _blockTimestamp() internal view virtual returns (uint32) {
        return uint32(block.timestamp);
    }

    function _getPool(IPoolManager.PoolKey memory key) private view returns (Pool.State storage) {
        return pools[keccak256(abi.encode(key))];
    }

    /// @notice Initialize the state for a given pool ID
    function initialize(IPoolManager.PoolKey memory key, uint160 sqrtPriceX96, uint256 twammExpiryInterval) external override returns (int24 tick) {
        if (key.hooks.shouldCallBeforeInitialize()) {
            key.hooks.beforeInitialize(msg.sender, key, sqrtPriceX96);
        }

        tick = _getPool(key).initialize(_blockTimestamp(), sqrtPriceX96, twammExpiryInterval);

        if (key.hooks.shouldCallAfterInitialize()) {
            key.hooks.afterInitialize(msg.sender, key, sqrtPriceX96, tick);
        }
    }

    /// @notice Increase the maximum number of stored observations for the pool's oracle
    function increaseObservationCardinalityNext(IPoolManager.PoolKey memory key, uint16 observationCardinalityNext)
        external
        override
        returns (uint16 observationCardinalityNextOld, uint16 observationCardinalityNextNew)
    {
        (observationCardinalityNextOld, observationCardinalityNextNew) = _getPool(key)
            .increaseObservationCardinalityNext(observationCardinalityNext);
    }

    /// @inheritdoc IPoolManager
    mapping(IERC20Minimal => uint256) public override reservesOf;

    /// @inheritdoc IPoolManager
    address[] public override lockedBy;

    /// @inheritdoc IPoolManager
    function lockedByLength() external view returns (uint256) {
        return lockedBy.length;
    }

    /// @member slot The slot in the tokensTouched array where the token is found
    /// @member delta The delta that is owed for that particular token
    struct PositionAndDelta {
        uint8 slot;
        int248 delta;
    }

    /// @member tokensTouched The tokens that have been touched by this locker
    /// @member tokenDelta The amount owed to the locker (positive) or owed to the pool (negative) of the token
    struct LockState {
        IERC20Minimal[] tokensTouched;
        mapping(IERC20Minimal => PositionAndDelta) tokenDelta;
    }

    /// @dev Represents the state of the locker at the given index. Each locker must have net 0 tokens owed before
    /// releasing their lock. Note this is private because the nested mappings cannot be exposed as a public variable.
    mapping(uint256 => LockState) private lockStates;

    /// @inheritdoc IPoolManager
    function getTokensTouchedLength(uint256 id) external view returns (uint256) {
        return lockStates[id].tokensTouched.length;
    }

    /// @inheritdoc IPoolManager
    function getTokensTouched(uint256 id, uint256 index) external view returns (IERC20Minimal) {
        return lockStates[id].tokensTouched[index];
    }

    /// @inheritdoc IPoolManager
    function getTokenDelta(uint256 id, IERC20Minimal token) external view returns (uint8 slot, int248 delta) {
        PositionAndDelta storage pd = lockStates[id].tokenDelta[token];
        (slot, delta) = (pd.slot, pd.delta);
    }

    function lock(bytes calldata data) external override returns (bytes memory result) {
        uint256 id = lockedBy.length;
        lockedBy.push(msg.sender);

        // the caller does everything in this callback, including paying what they owe via calls to settle
        result = ILockCallback(msg.sender).lockAcquired(data);

        unchecked {
            LockState storage lockState = lockStates[id];
            uint256 numTokensTouched = lockState.tokensTouched.length;
            for (uint256 i; i < numTokensTouched; i++) {
                IERC20Minimal token = lockState.tokensTouched[i];
                PositionAndDelta storage pd = lockState.tokenDelta[token];
                if (pd.delta != 0) revert TokenNotSettled(token, pd.delta);
                delete lockState.tokenDelta[token];
            }
            delete lockState.tokensTouched;
        }

        lockedBy.pop();
    }

    /// @dev Adds a token to a unique list of tokens that have been touched
    function _addTokenToSet(IERC20Minimal token) internal returns (uint8 slot) {
        LockState storage lockState = lockStates[lockedBy.length - 1];
        uint256 numTokensTouched = lockState.tokensTouched.length;
        if (numTokensTouched == 0) {
            lockState.tokensTouched.push(token);
            return 0;
        }

        PositionAndDelta storage pd = lockState.tokenDelta[token];
        slot = pd.slot;

        if (slot == 0 && lockState.tokensTouched[slot] != token) {
            if (numTokensTouched >= type(uint8).max) revert MaxTokensTouched();
            slot = uint8(numTokensTouched);
            pd.slot = slot;
            lockState.tokensTouched.push(token);
        }
    }

    function _accountDelta(IERC20Minimal token, int256 delta) internal {
        if (delta == 0) return;
        _addTokenToSet(token);
        lockStates[lockedBy.length - 1].tokenDelta[token].delta += delta.toInt248();
    }

    /// @dev Accumulates a balance change to a map of token to balance changes
    function _accountPoolBalanceDelta(PoolKey memory key, IPoolManager.BalanceDelta memory delta) internal {
        _accountDelta(key.token0, delta.amount0);
        _accountDelta(key.token1, delta.amount1);
    }

    modifier onlyByLocker() {
        address locker = lockedBy[lockedBy.length - 1];
        if (msg.sender != locker) revert LockedBy(locker);
        _;
    }

    /// @dev Modify the position
    function modifyPosition(IPoolManager.PoolKey memory key, IPoolManager.ModifyPositionParams memory params)
        external
        override
        noDelegateCall
        onlyByLocker
        returns (IPoolManager.BalanceDelta memory delta)
    {
        if (key.hooks.shouldCallBeforeModifyPosition()) {
            key.hooks.beforeModifyPosition(msg.sender, key, params);
        }

        delta = _getPool(key).modifyPosition(
            Pool.ModifyPositionParams({
                owner: msg.sender,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: params.liquidityDelta.toInt128(),
                time: _blockTimestamp(),
                maxLiquidityPerTick: Tick.tickSpacingToMaxLiquidityPerTick(key.tickSpacing),
                tickSpacing: key.tickSpacing
            })
        );

        _accountPoolBalanceDelta(key, delta);

        if (key.hooks.shouldCallAfterModifyPosition()) {
            key.hooks.afterModifyPosition(msg.sender, key, params, delta);
        }
    }

    function swap(IPoolManager.PoolKey memory key, IPoolManager.SwapParams memory params)
        public
        override
        noDelegateCall
        onlyByLocker
        returns (IPoolManager.BalanceDelta memory delta)
    {
        executeTWAMMOrders(key);

        if (key.hooks.shouldCallBeforeSwap()) {
            key.hooks.beforeSwap(msg.sender, key, params);
        }

        delta = _getPool(key).swap(
            Pool.SwapParams({
                time: _blockTimestamp(),
                fee: key.fee,
                tickSpacing: key.tickSpacing,
                zeroForOne: params.zeroForOne,
                amountSpecified: params.amountSpecified,
                sqrtPriceLimitX96: params.sqrtPriceLimitX96
            })
        );

        _accountPoolBalanceDelta(key, delta);

        if (key.hooks.shouldCallAfterSwap()) {
            key.hooks.afterSwap(msg.sender, key, params, delta);
        }
    }

    /// @notice Called by the user to net out some value owed to the user
    /// @dev Can also be used as a mechanism for _free_ flash loans
    function take(
        IERC20Minimal token,
        address to,
        uint256 amount
    ) external override noDelegateCall onlyByLocker {
        _accountDelta(token, amount.toInt256());
        reservesOf[token] -= amount;
        token.transfer(to, amount);
    }

    /// @notice Called by the user to pay what is owed
    function settle(IERC20Minimal token) external override noDelegateCall onlyByLocker returns (uint256 paid) {
        uint256 reservesBefore = reservesOf[token];
        reservesOf[token] = token.balanceOf(address(this));
        paid = reservesOf[token] - reservesBefore;
        // subtraction must be safe
        _accountDelta(token, -(paid.toInt256()));
    }

    /// @notice Update the protocol fee for a given pool
    function setFeeProtocol(IPoolManager.PoolKey calldata key, uint8 feeProtocol)
        external
        override
        returns (uint8 feeProtocolOld)
    {
        return _getPool(key).setFeeProtocol(feeProtocol);
    }

    /// @notice Observe a past state of a pool
    function observe(IPoolManager.PoolKey calldata key, uint32[] calldata secondsAgos)
        external
        view
        override
        noDelegateCall
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        return _getPool(key).observe(_blockTimestamp(), secondsAgos);
    }

    /// @notice Get the snapshot of the cumulative values of a tick range
    function snapshotCumulativesInside(
        IPoolManager.PoolKey calldata key,
        int24 tickLower,
        int24 tickUpper
    ) external view override noDelegateCall returns (Pool.Snapshot memory) {
        return _getPool(key).snapshotCumulativesInside(tickLower, tickUpper, _blockTimestamp());
    }

    function submitLongTermOrder(IPoolManager.PoolKey calldata key, TWAMM.LongTermOrderParams calldata params)
        external
        onlyByLocker
        returns (uint256 orderId)
    {
        executeTWAMMOrders(key);
        return _getPool(key).twamm.submitLongTermOrder(params);
    }

    function cancelLongTermOrder(IPoolManager.PoolKey calldata key, uint256 orderId)
        external
        onlyByLocker
        returns (uint256 amountOut0, uint256 amountOut1)
    {
        executeTWAMMOrders(key);

        (amountOut0, amountOut1) = _getPool(key).twamm.cancelLongTermOrder(orderId);

        IPoolManager.BalanceDelta memory delta = IPoolManager.BalanceDelta({
            amount0: -(amountOut0.toInt256()),
            amount1: -(amountOut1.toInt256())
        });
        _accountPoolBalanceDelta(key, delta);
    }

    function claimEarningsOnLongTermOrder(IPoolManager.PoolKey calldata key, uint256 orderId)
        external
        onlyByLocker
        returns (uint256 earningsAmount)
    {
        executeTWAMMOrders(key);

        uint8 sellTokenIndex;
        (earningsAmount, sellTokenIndex) = _getPool(key).twamm.claimEarnings(orderId);
        IERC20Minimal buyToken = sellTokenIndex == 0 ? key.token1 : key.token0;
        _accountDelta(buyToken, -(earningsAmount.toInt256()));
    }

    function executeTWAMMOrders(IPoolManager.PoolKey memory key)
        public
        onlyByLocker
        returns (uint256 earningsAmount)
    {
        Pool.State storage pool = _getPool(key);
        (bool zeroForOne, uint256 amountIn, uint160 sqrtPriceLimitX96) = pool.twamm.executeTWAMMOrders(
            TWAMM.PoolParamsOnExecute(pool.slot0.sqrtPriceX96, pool.liquidity, key.fee, key.tickSpacing),
            pool.ticks,
            pool.tickBitmap
        );
        if (amountIn > 0) {
            swap(key, SwapParams(zeroForOne, int256(amountIn), sqrtPriceLimitX96));
        }
    }
}
