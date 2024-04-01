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
import {IUnlockCallback} from "./interfaces/callback/IUnlockCallback.sol";
import {ProtocolFees} from "./ProtocolFees.sol";
import {ERC6909Claims} from "./ERC6909Claims.sol";
import {PoolId, PoolIdLibrary} from "./types/PoolId.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "./types/BalanceDelta.sol";
import {Lock} from "./libraries/Lock.sol";
import {CurrencyDelta} from "./libraries/CurrencyDelta.sol";
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

    /// @inheritdoc IPoolManager
    function currencyDelta(address caller, Currency currency) external view returns (int256) {
        return CurrencyDelta.get(caller, currency);
    }

    /// @inheritdoc IPoolManager
    function isUnlocked() external view override returns (bool) {
        return Lock.isUnlocked();
    }

    /// @notice This will revert if the contract is locked
    modifier onlyWhenUnlocked() {
        if (!Lock.isUnlocked()) revert ManagerLocked();
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
    function unlock(bytes calldata data) external override returns (bytes memory result) {
        if (Lock.isUnlocked()) revert AlreadyUnlocked();

        Lock.unlock();

        // the caller does everything in this callback, including paying what they owe via calls to settle
        result = IUnlockCallback(msg.sender).unlockCallback(data);

        if (NonZeroDeltaCount.read() != 0) revert CurrencyNotSettled();
        Lock.lock();
    }

    function _accountDelta(Currency currency, int128 delta, address target) internal {
        if (delta == 0) return;

        int256 current = CurrencyDelta.get(target, currency);
        int256 next = current + delta;

        unchecked {
            if (next == 0) {
                NonZeroDeltaCount.decrement();
            } else if (current == 0) {
                NonZeroDeltaCount.increment();
            }
        }

        CurrencyDelta.set(target, currency, next);
    }

    /// @dev Accumulates a balance change to a map of currency to balance changes
    function _accountPoolBalanceDelta(PoolKey memory key, BalanceDelta delta, address target) internal {
        _accountDelta(key.currency0, delta.amount0(), target);
        _accountDelta(key.currency1, delta.amount1(), target);
    }

    function _checkPoolInitialized(PoolId id) internal view {
        if (pools[id].isNotInitialized()) revert PoolNotInitialized();
    }

    /// @inheritdoc IPoolManager
    function modifyLiquidity(
        PoolKey memory key,
        IPoolManager.ModifyLiquidityParams memory params,
        bytes calldata hookData
    ) external override noDelegateCall onlyWhenUnlocked returns (BalanceDelta delta) {
        PoolId id = key.toId();
        _checkPoolInitialized(id);

        key.hooks.beforeModifyLiquidity(key, params, hookData);

        delta = pools[id].modifyLiquidity(
            Pool.ModifyLiquidityParams({
                owner: msg.sender,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: params.liquidityDelta.toInt128(),
                tickSpacing: key.tickSpacing
            })
        );

        emit ModifyLiquidity(id, msg.sender, params.tickLower, params.tickUpper, params.liquidityDelta);

        BalanceDelta hookDelta = key.hooks.afterModifyLiquidity(key, params, delta, hookData);
        delta = delta - hookDelta;

        _accountPoolBalanceDelta(key, hookDelta, address(key.hooks));
        _accountPoolBalanceDelta(key, delta, msg.sender);
    }

    /// @inheritdoc IPoolManager
    function swap(PoolKey memory key, IPoolManager.SwapParams memory params, bytes calldata hookData)
        external
        override
        noDelegateCall
        onlyWhenUnlocked
        returns (BalanceDelta delta)
    {
        PoolId id = key.toId();
        _checkPoolInitialized(id);

        (int256 amountToSwap, int128 hookDeltaInSpecified, uint24 fee) = key.hooks.beforeSwap(key, params, hookData);
        // execute swap, account protocol fees, and emit swap event
        delta = _swap(
            id,
            Pool.SwapParams({
                tickSpacing: key.tickSpacing,
                zeroForOne: params.zeroForOne,
                amountSpecified: amountToSwap,
                sqrtPriceLimitX96: params.sqrtPriceLimitX96,
                fee: fee
            }),
            params.zeroForOne ? key.currency0 : key.currency1
        );

        (int128 hookDeltaInUnspecified) = key.hooks.afterSwap(key, params, delta, hookData);

        // calculates if currency0 or currency1 is the specified token
        BalanceDelta hookDelta = ((params.amountSpecified < 0) == params.zeroForOne)
            ? toBalanceDelta(hookDeltaInSpecified, hookDeltaInUnspecified)
            : toBalanceDelta(hookDeltaInUnspecified, hookDeltaInSpecified);
        delta = delta - hookDelta;

        // Account the hook's delta to the hook's address, and charge them to the caller's deltas
        _accountPoolBalanceDelta(key, hookDelta, address(key.hooks));
        _accountPoolBalanceDelta(key, delta, msg.sender);
    }

    // Internal swap function to execute a swap, account protocol fees, and emit the swap event
    function _swap(PoolId id, Pool.SwapParams memory params, Currency inputCurrency) internal returns (BalanceDelta) {
        (BalanceDelta delta, uint256 feeForProtocol, uint24 swapFee, Pool.SwapState memory state) =
            pools[id].swap(params);

        // the fee is on the input currency
        unchecked {
            if (feeForProtocol > 0) {
                protocolFeesAccrued[inputCurrency] += feeForProtocol;
            }
        }

        emit Swap(
            id, msg.sender, delta.amount0(), delta.amount1(), state.sqrtPriceX96, state.liquidity, state.tick, swapFee
        );

        return delta;
    }

    /// @inheritdoc IPoolManager
    function donate(PoolKey memory key, uint256 amount0, uint256 amount1, bytes calldata hookData)
        external
        override
        noDelegateCall
        onlyWhenUnlocked
        returns (BalanceDelta delta)
    {
        PoolId id = key.toId();
        _checkPoolInitialized(id);

        key.hooks.beforeDonate(key, amount0, amount1, hookData);

        delta = pools[id].donate(amount0, amount1);

        _accountPoolBalanceDelta(key, delta, msg.sender);

        key.hooks.afterDonate(key, amount0, amount1, hookData);
    }

    /// @inheritdoc IPoolManager
    function take(Currency currency, address to, uint256 amount) external override noDelegateCall onlyWhenUnlocked {
        // subtraction must be safe
        _accountDelta(currency, -(amount.toInt128()), msg.sender);
        if (!currency.isNative()) reservesOf[currency] -= amount;
        currency.transfer(to, amount);
    }

    /// @inheritdoc IPoolManager
    function settle(Currency currency)
        external
        payable
        override
        noDelegateCall
        onlyWhenUnlocked
        returns (uint256 paid)
    {
        if (currency.isNative()) {
            paid = msg.value;
        } else {
            uint256 reservesBefore = reservesOf[currency];
            reservesOf[currency] = currency.balanceOfSelf();
            paid = reservesOf[currency] - reservesBefore;
        }

        _accountDelta(currency, paid.toInt128(), msg.sender);
    }

    /// @inheritdoc IPoolManager
    function mint(address to, uint256 id, uint256 amount) external override noDelegateCall onlyWhenUnlocked {
        // subtraction must be safe
        _accountDelta(CurrencyLibrary.fromId(id), -(amount.toInt128()), msg.sender);
        _mint(to, id, amount);
    }

    /// @inheritdoc IPoolManager
    function burn(address from, uint256 id, uint256 amount) external override noDelegateCall onlyWhenUnlocked {
        _accountDelta(CurrencyLibrary.fromId(id), amount.toInt128(), msg.sender);
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

    function getNonzeroDeltaCount() external view returns (uint256 _nonzeroDeltaCount) {
        return NonZeroDeltaCount.read();
    }

    function getPoolTickInfo(PoolId id, int24 tick) external view returns (Pool.TickInfo memory) {
        return pools[id].getPoolTickInfo(tick);
    }

    function getPoolBitmapInfo(PoolId id, int16 word) external view returns (uint256 tickBitmap) {
        return pools[id].getPoolBitmapInfo(word);
    }
}
