// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Hooks} from "./libraries/Hooks.sol";
import {Pool} from "./libraries/Pool.sol";
import {SafeCast} from "./libraries/SafeCast.sol";
import {Position} from "./libraries/Position.sol";
import {FeeLibrary} from "./libraries/FeeLibrary.sol";
import {Currency, CurrencyLibrary} from "./types/Currency.sol";
import {PoolKey} from "./types/PoolKey.sol";
import {TickMath} from "./libraries/TickMath.sol";
import {NoDelegateCall} from "./NoDelegateCall.sol";
import {Owned} from "./Owned.sol";
import {IHooks} from "./interfaces/IHooks.sol";
import {IDynamicFeeManager} from "./interfaces/IDynamicFeeManager.sol";
import {IPoolManager} from "./interfaces/IPoolManager.sol";
import {ILockCallback} from "./interfaces/callback/ILockCallback.sol";
import {Fees} from "./Fees.sol";
import {ERC6909Claims} from "./ERC6909Claims.sol";
import {PoolId, PoolIdLibrary} from "./types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "./types/BalanceDelta.sol";
import {Lockers} from "./libraries/Lockers.sol";
import {PoolGetters} from "./libraries/PoolGetters.sol";

/// @notice Holds the state for all pools
contract PoolManager is IPoolManager, Fees, NoDelegateCall, ERC6909Claims {
    using PoolIdLibrary for PoolKey;
    using SafeCast for *;
    using Pool for *;
    using Hooks for IHooks;
    using Position for mapping(bytes32 => Position.Info);
    using CurrencyLibrary for Currency;
    using FeeLibrary for uint24;
    using PoolGetters for Pool.State;

    /// @inheritdoc IPoolManager
    int24 public constant MAX_TICK_SPACING = TickMath.MAX_TICK_SPACING;

    /// @inheritdoc IPoolManager
    int24 public constant MIN_TICK_SPACING = TickMath.MIN_TICK_SPACING;

    /// @dev Represents the currencies due/owed to each locker.
    /// Must all net to zero when the last lock is released.
    /// TODO this needs to be transient
    mapping(address locker => mapping(Currency currency => int256 currencyDelta)) public currencyDelta;

    /// @inheritdoc IPoolManager
    mapping(Currency currency => uint256) public override reservesOf;

    mapping(PoolId id => Pool.State) public pools;

    constructor(uint256 controllerGasLimit) Fees(controllerGasLimit) {}

    /// @inheritdoc IPoolManager
    function getSlot0(PoolId id)
        external
        view
        override
        returns (uint160 sqrtPriceX96, int24 tick, uint16 protocolFee)
    {
        Pool.Slot0 memory slot0 = pools[id].slot0;

        return (slot0.sqrtPriceX96, slot0.tick, slot0.protocolFee);
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

    /// @inheritdoc IPoolManager
    function getLock(uint256 i) external view override returns (address locker, address lockCaller) {
        return (Lockers.getLocker(i), Lockers.getLockCaller(i));
    }

    /// @notice This will revert if a function is called by any address other than the current locker OR the most recently called, pre-permissioned hook.
    modifier onlyByLocker() {
        _checkLocker(msg.sender, Lockers.getCurrentLocker(), Lockers.getCurrentHook());
        _;
    }

    function _checkLocker(address caller, address locker, IHooks hook) internal pure {
        if (caller == locker) return;
        if (caller == address(hook) && hook.hasPermission(Hooks.ACCESS_LOCK_FLAG)) return;
        revert LockedBy(locker, address(hook));
    }

    /// @inheritdoc IPoolManager
    function initialize(PoolKey memory key, uint160 sqrtPriceX96, bytes calldata hookData)
        external
        override
        onlyByLocker
        returns (int24 tick)
    {
        if (key.fee.isStaticFeeTooLarge()) revert FeeTooLarge();

        // see TickBitmap.sol for overflow conditions that can arise from tick spacing being too large
        if (key.tickSpacing > MAX_TICK_SPACING) revert TickSpacingTooLarge();
        if (key.tickSpacing < MIN_TICK_SPACING) revert TickSpacingTooSmall();
        if (key.currency0 >= key.currency1) revert CurrenciesOutOfOrderOrEqual();
        if (!key.hooks.isValidHookAddress(key.fee)) revert Hooks.HookAddressNotValid(address(key.hooks));

        key.hooks.beforeInitialize(key, sqrtPriceX96, hookData);

        PoolId id = key.toId();
        (, uint16 protocolFee) = _fetchProtocolFee(key);
        uint24 swapFee = key.fee.isDynamicFee() ? _fetchDynamicSwapFee(key) : key.fee.getStaticFee();

        tick = pools[id].initialize(sqrtPriceX96, protocolFee, swapFee);

        key.hooks.afterInitialize(key, sqrtPriceX96, tick, hookData);

        // On intitalize we emit the key's fee, which tells us all fee settings a pool can have: either a static swap fee or dynamic swap fee and if the hook has enabled swap or withdraw fees.
        emit Initialize(id, key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks);
    }

    /// @inheritdoc IPoolManager
    function lock(address lockTarget, bytes calldata data) external payable override returns (bytes memory result) {
        Lockers.push(lockTarget, msg.sender);

        // the caller does everything in this callback, including paying what they owe via calls to settle
        result = ILockCallback(lockTarget).lockAcquired(msg.sender, data);

        if (Lockers.length() == 1) {
            if (Lockers.nonzeroDeltaCount() != 0) revert CurrencyNotSettled();
            Lockers.clear();
        } else {
            Lockers.pop();
        }
    }

    function _accountDelta(Currency currency, int128 delta) internal {
        if (delta == 0) return;

        address locker = Lockers.getCurrentLocker();
        int256 current = currencyDelta[locker][currency];
        int256 next = current + delta;

        unchecked {
            if (next == 0) {
                Lockers.decrementNonzeroDeltaCount();
            } else if (current == 0) {
                Lockers.incrementNonzeroDeltaCount();
            }
        }

        currencyDelta[locker][currency] = next;
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
    ) external override noDelegateCall onlyByLocker returns (BalanceDelta delta) {
        PoolId id = key.toId();
        _checkPoolInitialized(id);

        if (!key.hooks.beforeModifyLiquidity(key, params, hookData)) {
            return BalanceDeltaLibrary.MAXIMUM_DELTA;
        }

        delta = pools[id].modifyPosition(
            Pool.ModifyPositionParams({
                owner: msg.sender,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: params.liquidityDelta.toInt128(),
                tickSpacing: key.tickSpacing
            })
        );

        _accountPoolBalanceDelta(key, delta);

        key.hooks.afterModifyLiquidity(key, params, delta, hookData);

        emit ModifyLiquidity(id, msg.sender, params.tickLower, params.tickUpper, params.liquidityDelta);
    }

    /// @inheritdoc IPoolManager
    function swap(PoolKey memory key, IPoolManager.SwapParams memory params, bytes calldata hookData)
        external
        override
        noDelegateCall
        onlyByLocker
        returns (BalanceDelta delta)
    {
        PoolId id = key.toId();
        _checkPoolInitialized(id);

        if (!key.hooks.beforeSwap(key, params, hookData)) {
            return BalanceDeltaLibrary.MAXIMUM_DELTA;
        }

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

        key.hooks.afterSwap(key, params, delta, hookData);

        emit Swap(
            id, msg.sender, delta.amount0(), delta.amount1(), state.sqrtPriceX96, state.liquidity, state.tick, swapFee
        );
    }

    /// @inheritdoc IPoolManager
    function donate(PoolKey memory key, uint256 amount0, uint256 amount1, bytes calldata hookData)
        external
        override
        noDelegateCall
        onlyByLocker
        returns (BalanceDelta delta)
    {
        PoolId id = key.toId();
        _checkPoolInitialized(id);

        if (!key.hooks.beforeDonate(key, amount0, amount1, hookData)) {
            return BalanceDeltaLibrary.MAXIMUM_DELTA;
        }

        delta = pools[id].donate(amount0, amount1);

        _accountPoolBalanceDelta(key, delta);

        key.hooks.afterDonate(key, amount0, amount1, hookData);
    }

    /// @inheritdoc IPoolManager
    function take(Currency currency, address to, uint256 amount) external override noDelegateCall onlyByLocker {
        _accountDelta(currency, amount.toInt128());
        reservesOf[currency] -= amount;
        currency.transfer(to, amount);
    }

    /// @inheritdoc IPoolManager
    function settle(Currency currency) external payable override noDelegateCall onlyByLocker returns (uint256 paid) {
        uint256 reservesBefore = reservesOf[currency];
        reservesOf[currency] = currency.balanceOfSelf();
        paid = reservesOf[currency] - reservesBefore;
        // subtraction must be safe
        _accountDelta(currency, -(paid.toInt128()));
    }

    /// @inheritdoc IPoolManager
    function mint(address to, uint256 id, uint256 amount) external override noDelegateCall onlyByLocker {
        _accountDelta(CurrencyLibrary.fromId(id), amount.toInt128());
        _mint(to, id, amount);
    }

    /// @inheritdoc IPoolManager
    function burn(address from, uint256 id, uint256 amount) external override noDelegateCall onlyByLocker {
        _accountDelta(CurrencyLibrary.fromId(id), -(amount.toInt128()));
        _burnFrom(from, id, amount);
    }

    function setProtocolFee(PoolKey memory key) external {
        (bool success, uint16 newProtocolFee) = _fetchProtocolFee(key);
        if (!success) revert ProtocolFeeControllerCallFailedOrInvalidResult();
        PoolId id = key.toId();
        pools[id].setProtocolFee(newProtocolFee);
        emit ProtocolFeeUpdated(id, newProtocolFee);
    }

    function updateDynamicSwapFee(PoolKey memory key) external {
        if (key.fee.isDynamicFee()) {
            uint24 newDynamicSwapFee = _fetchDynamicSwapFee(key);
            PoolId id = key.toId();
            pools[id].setSwapFee(newDynamicSwapFee);
            emit DynamicSwapFeeUpdated(id, newDynamicSwapFee);
        } else {
            revert FeeNotDynamic();
        }
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

    function getLockLength() external view returns (uint256 _length) {
        return Lockers.length();
    }

    function getLockNonzeroDeltaCount() external view returns (uint256 _nonzeroDeltaCount) {
        return Lockers.nonzeroDeltaCount();
    }

    function getCurrentHook() external view returns (IHooks) {
        return Lockers.getCurrentHook();
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
