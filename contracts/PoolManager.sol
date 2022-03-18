// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {Pool} from './libraries/Pool.sol';
import {Tick} from './libraries/Tick.sol';
import {SafeCast} from './libraries/SafeCast.sol';
import {TWAMM} from './libraries/TWAMM.sol';

import {IERC20Minimal} from './interfaces/external/IERC20Minimal.sol';
import {NoDelegateCall} from './NoDelegateCall.sol';
import {IPoolManager} from './interfaces/IPoolManager.sol';
import {ILockCallback} from './interfaces/callback/ILockCallback.sol';

/// @notice Holds the state for all pools
contract PoolManager is IPoolManager, NoDelegateCall {
    using TWAMM for TWAMM.State;
    using SafeCast for *;
    using Pool for *;

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
    function initialize(
        IPoolManager.PoolKey memory key,
        uint160 sqrtPriceX96,
        uint256 twammExpiryInterval
    ) external override returns (int24 tick) {
        tick = _getPool(key).initialize(_blockTimestamp(), sqrtPriceX96, twammExpiryInterval);
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

    /// @notice Represents the address that has currently locked the pool
    address public override lockedBy;

    /// @notice All the latest tracked balances of tokens
    mapping(IERC20Minimal => uint256) public override reservesOf;

    /// @notice Internal transient enumerable set
    IERC20Minimal[] public override tokensTouched;
    struct PositionAndDelta {
        uint8 slot;
        int248 delta;
    }
    mapping(IERC20Minimal => PositionAndDelta) public override tokenDelta;

    function lock(bytes calldata data) external override returns (bytes memory result) {
        require(lockedBy == address(0));
        lockedBy = msg.sender;

        // the caller does everything in this callback, including paying what they owe via calls to settle
        result = ILockCallback(msg.sender).lockAcquired(data);

        unchecked {
            for (uint256 i = 0; i < tokensTouched.length; i++) {
                if (tokenDelta[tokensTouched[i]].delta != 0)
                    revert TokenNotSettled(tokensTouched[i], tokenDelta[tokensTouched[i]].delta);
                delete tokenDelta[tokensTouched[i]];
            }
        }
        delete tokensTouched;
        delete lockedBy;
    }

    /// @dev Adds a token to a unique list of tokens that have been touched
    function _addTokenToSet(IERC20Minimal token) internal returns (uint8 slot) {
        uint256 len = tokensTouched.length;
        if (len == 0) {
            tokensTouched.push(token);
            return 0;
        }

        PositionAndDelta storage pd = tokenDelta[token];
        slot = pd.slot;

        if (slot == 0 && tokensTouched[slot] != token) {
            require(len < type(uint8).max);
            slot = uint8(len);
            pd.slot = slot;
            tokensTouched.push(token);
        }
    }

    function _accountDelta(IERC20Minimal token, int256 delta) internal {
        if (delta == 0) return;
        _addTokenToSet(token);
        tokenDelta[token].delta += int248(delta);
    }

    /// @dev Accumulates a balance change to a map of token to balance changes
    function _accountPoolBalanceDelta(PoolKey memory key, Pool.BalanceDelta memory delta) internal {
        _accountDelta(key.token0, delta.amount0);
        _accountDelta(key.token1, delta.amount1);
    }

    modifier onlyByLocker() {
        if (msg.sender != lockedBy) revert LockedBy(lockedBy);
        _;
    }

    /// @dev Modify the position
    function modifyPosition(IPoolManager.PoolKey memory key, IPoolManager.ModifyPositionParams memory params)
        external
        override
        noDelegateCall
        onlyByLocker
        returns (Pool.BalanceDelta memory delta)
    {
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
    }

    function swap(IPoolManager.PoolKey memory key, IPoolManager.SwapParams memory params)
        external
        override
        noDelegateCall
        onlyByLocker
        returns (Pool.BalanceDelta memory delta)
    {
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
        returns (uint256 unsoldAmount, uint256 purchasedAmount)
    {
        executeTWAMMOrders(key);

        uint8 sellTokenIndex;
        (unsoldAmount, purchasedAmount, sellTokenIndex) = _getPool(key).twamm.cancelLongTermOrder(orderId);

        (uint256 amount0, uint256 amount1) = sellTokenIndex == 0
            ? (unsoldAmount, purchasedAmount)
            : (purchasedAmount, unsoldAmount);

        Pool.BalanceDelta memory delta = Pool.BalanceDelta({
            amount0: -(amount0.toInt256()),
            amount1: -(amount1.toInt256())
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

    function executeTWAMMOrders(IPoolManager.PoolKey calldata key)
        public
        onlyByLocker
        returns (uint256 earningsAmount)
    {
        Pool.State storage pool = _getPool(key);

        pool.twamm.executeTWAMMOrders(TWAMM.PoolParamsOnExecute(pool.slot0.sqrtPriceX96, pool.liquidity), pool.ticks);
    }
}
