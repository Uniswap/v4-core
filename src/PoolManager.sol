// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Hooks} from "./libraries/Hooks.sol";
import {Pool} from "./libraries/Pool.sol";
import {SafeCast} from "./libraries/SafeCast.sol";
import {Position} from "./libraries/Position.sol";
import {SwapFeeLibrary} from "./libraries/SwapFeeLibrary.sol";
import {Currency, CurrencyLibrary} from "./types/Currency.sol";
import {PoolKey} from "./types/PoolKey.sol";
import {TickMath} from "./libraries/TickMath.sol";
import {NoDelegateCall} from "./NoDelegateCall.sol";
import {Owned} from "./Owned.sol";
import {IHooks} from "./interfaces/IHooks.sol";
import {IPoolManager} from "./interfaces/IPoolManager.sol";
import {ILockCallback} from "./interfaces/callback/ILockCallback.sol";
import {ProtocolFees} from "./ProtocolFees.sol";
import {ERC6909Claims} from "./ERC6909Claims.sol";
import {PoolId, PoolIdLibrary} from "./types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "./types/BalanceDelta.sol";
import {Lock} from "./libraries/Lock.sol";
import {NonZeroDeltaCount} from "./libraries/NonZeroDeltaCount.sol";
import {PoolGetters} from "./libraries/PoolGetters.sol";

/// @notice Holds the state for all pools
contract PoolManager is IPoolManager, ProtocolFees, NoDelegateCall, ERC6909Claims {
    using PoolIdLibrary for PoolKey;
    using SafeCast for *;
    using Pool for *;
    using Hooks for IHooks;
    using Position for mapping(bytes32 => Position.Info);
    using CurrencyLibrary for Currency;
    using SwapFeeLibrary for uint24;
    using PoolGetters for Pool.State;

    /// @inheritdoc IPoolManager
    int24 public constant MAX_TICK_SPACING = TickMath.MAX_TICK_SPACING;

    /// @inheritdoc IPoolManager
    int24 public constant MIN_TICK_SPACING = TickMath.MIN_TICK_SPACING;

    /// @dev Represents the currencies due/owed to each caller.
    /// Must all net to zero when the lock is released.
    /// TODO this needs to be transient
    mapping(address caller => mapping(Currency currency => int256 currencyDelta)) public currencyDelta;

    /// @inheritdoc IPoolManager
    mapping(Currency currency => uint256) public override reservesOf;

    mapping(PoolId id => Pool.State) public pools;

    constructor(uint256 controllerGasLimit) ProtocolFees(controllerGasLimit) {}

    /// @inheritdoc IPoolManager
    function getSlot0(PoolId id)
        external
        view
        override
        returns (uint160 sqrtPriceX96, int24 tick, uint16 protocolFee, uint24 swapFee)
    {
        Pool.Slot0 memory slot0 = pools[id].slot0;

        return (slot0.sqrtPriceX96, slot0.tick, slot0.protocolFee, slot0.swapFee);
    }

    /// @inheritdoc IPoolManager
    function getLiquidity(PoolId id) external view override returns (uint128 liquidity) {
        return pools[id].liquidity;
    }

    /// @inheritdoc IPoolManager
    function getLiquidity(PoolId id, address _owner, int24 tickLower, int24 tickUpper)
        external
        view
        override
        returns (uint128 liquidity)
    {
        return pools[id].positions.get(_owner, tickLower, tickUpper).liquidity;
    }

    function getPosition(PoolId id, address _owner, int24 tickLower, int24 tickUpper)
        external
        view
        override
        returns (Position.Info memory position)
    {
        return pools[id].positions.get(_owner, tickLower, tickUpper);
    }

    function isLockSet() external view returns (bool) {
        return Lock.isLocked();
    }

    /// @notice This will revert if the contract is not locked
    modifier isLocked() {
        if (!Lock.isLocked()) revert ManagerNotLocked();
        _;
    }

    /// @inheritdoc IPoolManager
    function initialize(PoolKey memory key, uint160 sqrtPriceX96, bytes calldata hookData)
        external
        override
        returns (int24 tick)
    {
        // see TickBitmap.sol for overflow conditions that can arise from tick spacing being too large
        if (key.tickSpacing > MAX_TICK_SPACING) revert TickSpacingTooLarge();
        if (key.tickSpacing < MIN_TICK_SPACING) revert TickSpacingTooSmall();
        if (key.currency0 >= key.currency1) revert CurrenciesOutOfOrderOrEqual();
        if (!key.hooks.isValidHookAddress(key.fee)) revert Hooks.HookAddressNotValid(address(key.hooks));

        uint24 swapFee = key.fee.getSwapFee();

        key.hooks.beforeInitialize(key, sqrtPriceX96, hookData);

        PoolId id = key.toId();
        (, uint16 protocolFee) = _fetchProtocolFee(key);

        tick = pools[id].initialize(sqrtPriceX96, protocolFee, swapFee);

        key.hooks.afterInitialize(key, sqrtPriceX96, tick, hookData);

        // On intitalize we emit the key's fee, which tells us all fee settings a pool can have: either a static swap fee or dynamic swap fee and if the hook has enabled swap or withdraw fees.
        emit Initialize(id, key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks);
    }

    /// @inheritdoc IPoolManager
    function lock(bytes calldata data) external payable override returns (bytes memory result) {
        if (Lock.isLocked()) revert AlreadyLocked();

        Lock.lock();

        // the caller does everything in this callback, including paying what they owe via calls to settle
        result = ILockCallback(msg.sender).lockAcquired(data);

        if (NonZeroDeltaCount.read() != 0) revert CurrencyNotSettled();
        Lock.unlock();
    }

    function _accountDelta(Currency currency, int128 delta) internal {
        if (delta == 0) return;

        int256 current = currencyDelta[msg.sender][currency];
        int256 next = current + delta;

        unchecked {
            if (next == 0) {
                NonZeroDeltaCount.decrement();
            } else if (current == 0) {
                NonZeroDeltaCount.increment();
            }
        }

        currencyDelta[msg.sender][currency] = next;
    }

    /// @dev Accumulates a balance change to a map of currency to balance changes
    function _accountPoolBalanceDelta(PoolKey memory key, BalanceDelta delta) internal {
        _accountDelta(key.currency0, delta.amount0());
        _accountDelta(key.currency1, delta.amount1());
    }

    function _checkPoolInitialized(PoolId id) internal view {
        if (pools[id].isNotInitialized()) revert PoolNotInitialized();
    }

    /// @inheritdoc IPoolManager
    function modifyLiquidity(
        PoolKey memory key,
        IPoolManager.ModifyLiquidityParams memory params,
        bytes calldata hookData
    ) external override noDelegateCall isLocked returns (BalanceDelta delta) {
        PoolId id = key.toId();
        _checkPoolInitialized(id);

        key.hooks.beforeModifyLiquidity(key, params, hookData);

        delta = pools[id].modifyLiquidity(
            Pool.ModifyPositionParams({
                owner: msg.sender,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: params.liquidityDelta.toInt128(),
                tickSpacing: key.tickSpacing
            })
        );

        _accountPoolBalanceDelta(key, delta);

        emit ModifyLiquidity(id, msg.sender, params.tickLower, params.tickUpper, params.liquidityDelta);

        key.hooks.afterModifyLiquidity(key, params, delta, hookData);
    }

    /// @inheritdoc IPoolManager
    function swap(PoolKey memory key, IPoolManager.SwapParams memory params, bytes calldata hookData)
        external
        override
        noDelegateCall
        isLocked
        returns (BalanceDelta delta)
    {
        PoolId id = key.toId();
        _checkPoolInitialized(id);

        key.hooks.beforeSwap(key, params, hookData);

        uint256 feeForProtocol;
        uint24 swapFee;
        Pool.SwapState memory state;
        (delta, feeForProtocol, swapFee, state) = pools[id].swap(
            Pool.SwapParams({
                tickSpacing: key.tickSpacing,
                zeroForOne: params.zeroForOne,
                amountSpecified: params.amountSpecified,
                sqrtPriceLimitX96: params.sqrtPriceLimitX96
            })
        );

        _accountPoolBalanceDelta(key, delta);

        // the fee is on the input currency
        unchecked {
            if (feeForProtocol > 0) {
                protocolFeesAccrued[params.zeroForOne ? key.currency0 : key.currency1] += feeForProtocol;
            }
        }

        emit Swap(
            id, msg.sender, delta.amount0(), delta.amount1(), state.sqrtPriceX96, state.liquidity, state.tick, swapFee
        );

        key.hooks.afterSwap(key, params, delta, hookData);
    }

    /// @inheritdoc IPoolManager
    function donate(PoolKey memory key, uint256 amount0, uint256 amount1, bytes calldata hookData)
        external
        override
        noDelegateCall
        isLocked
        returns (BalanceDelta delta)
    {
        PoolId id = key.toId();
        _checkPoolInitialized(id);

        key.hooks.beforeDonate(key, amount0, amount1, hookData);

        delta = pools[id].donate(amount0, amount1);

        _accountPoolBalanceDelta(key, delta);

        key.hooks.afterDonate(key, amount0, amount1, hookData);
    }

    /// @inheritdoc IPoolManager
    function take(Currency currency, address to, uint256 amount) external override noDelegateCall isLocked {
        // subtraction must be safe
        _accountDelta(currency, -(amount.toInt128()));
        reservesOf[currency] -= amount;
        currency.transfer(to, amount);
    }

    /// @inheritdoc IPoolManager
    function settle(Currency currency) external payable override noDelegateCall isLocked returns (uint256 paid) {
        uint256 reservesBefore = reservesOf[currency];
        reservesOf[currency] = currency.balanceOfSelf();
        paid = reservesOf[currency] - reservesBefore;
        _accountDelta(currency, paid.toInt128());
    }

    /// @inheritdoc IPoolManager
    function mint(address to, uint256 id, uint256 amount) external override noDelegateCall isLocked {
        // subtraction must be safe
        _accountDelta(CurrencyLibrary.fromId(id), -(amount.toInt128()));
        _mint(to, id, amount);
    }

    /// @inheritdoc IPoolManager
    function burn(address from, uint256 id, uint256 amount) external override noDelegateCall isLocked {
        _accountDelta(CurrencyLibrary.fromId(id), amount.toInt128());
        _burnFrom(from, id, amount);
    }

    function setProtocolFee(PoolKey memory key) external {
        (bool success, uint16 newProtocolFee) = _fetchProtocolFee(key);
        if (!success) revert ProtocolFeeControllerCallFailedOrInvalidResult();
        PoolId id = key.toId();
        pools[id].setProtocolFee(newProtocolFee);
        emit ProtocolFeeUpdated(id, newProtocolFee);
    }

    function updateDynamicSwapFee(PoolKey memory key, uint24 newDynamicSwapFee) external {
        if (!key.fee.isDynamicFee() || msg.sender != address(key.hooks)) revert UnauthorizedDynamicSwapFeeUpdate();
        newDynamicSwapFee.validate();
        PoolId id = key.toId();
        pools[id].setSwapFee(newDynamicSwapFee);
    }

    function extsload(bytes32 slot) external view returns (bytes32 value) {
        /// @solidity memory-safe-assembly
        assembly {
            value := sload(slot)
        }
    }

    function extsload(bytes32 startSlot, uint256 nSlots) external view returns (bytes memory) {
        bytes memory value = new bytes(32 * nSlots);

        /// @solidity memory-safe-assembly
        assembly {
            for { let i := 0 } lt(i, nSlots) { i := add(i, 1) } {
                mstore(add(value, mul(add(i, 1), 32)), sload(add(startSlot, i)))
            }
        }

        return value;
    }

    function getLockNonzeroDeltaCount() external view returns (uint256 _nonzeroDeltaCount) {
        return NonZeroDeltaCount.read();
    }

    function getPoolTickInfo(PoolId id, int24 tick) external view returns (Pool.TickInfo memory) {
        return pools[id].getPoolTickInfo(tick);
    }

    function getPoolBitmapInfo(PoolId id, int16 word) external view returns (uint256 tickBitmap) {
        return pools[id].getPoolBitmapInfo(word);
    }

    /// @notice receive native tokens for native pools
    receive() external payable {}
}
