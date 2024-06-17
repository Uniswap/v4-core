// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Hooks} from "./libraries/Hooks.sol";
import {Pool} from "./libraries/Pool.sol";
import {SafeCast} from "./libraries/SafeCast.sol";
import {Position} from "./libraries/Position.sol";
import {LPFeeLibrary} from "./libraries/LPFeeLibrary.sol";
import {Currency, CurrencyLibrary} from "./types/Currency.sol";
import {PoolKey} from "./types/PoolKey.sol";
import {TickMath} from "./libraries/TickMath.sol";
import {NoDelegateCall} from "./NoDelegateCall.sol";
import {IHooks} from "./interfaces/IHooks.sol";
import {IPoolManager} from "./interfaces/IPoolManager.sol";
import {IUnlockCallback} from "./interfaces/callback/IUnlockCallback.sol";
import {ProtocolFees} from "./ProtocolFees.sol";
import {ERC6909Claims} from "./ERC6909Claims.sol";
import {PoolId, PoolIdLibrary} from "./types/PoolId.sol";
import {BalanceDeltas, BalanceDeltasLibrary, toBalanceDeltas} from "./types/BalanceDeltas.sol";
import {BeforeSwapDeltas} from "./types/BeforeSwapDeltas.sol";
import {Lock} from "./libraries/Lock.sol";
import {CurrencyDelta} from "./libraries/CurrencyDelta.sol";
import {NonZeroDeltaCount} from "./libraries/NonZeroDeltaCount.sol";
import {Reserves} from "./libraries/Reserves.sol";
import {Extsload} from "./Extsload.sol";
import {Exttload} from "./Exttload.sol";
import {CustomRevert} from "./libraries/CustomRevert.sol";

//  4
//   44
//     444
//       444                   4444
//        4444            4444     4444
//          4444          4444444    4444                           4
//            4444        44444444     4444                         4
//             44444       4444444       4444444444444444       444444
//           4   44444     44444444       444444444444444444444    4444
//            4    44444    4444444         4444444444444444444444  44444
//             4     444444  4444444         44444444444444444444444 44  4
//              44     44444   444444          444444444444444444444 4     4
//               44      44444   44444           4444444444444444444 4 44
//                44       4444     44             444444444444444     444
//                444     4444                        4444444
//               4444444444444                     44                      4
//              44444444444                        444444     444444444    44
//             444444           4444               4444     4444444444      44
//             4444           44    44              4      44444444444
//            44444          444444444                   444444444444    4444
//            44444          44444444                  4444  44444444    444444
//            44444                                  4444   444444444    44444444
//           44444                                 4444     44444444    4444444444
//          44444                                4444      444444444   444444444444
//         44444                               4444        44444444    444444444444
//       4444444                             4444          44444444         4444444
//      4444444                            44444          44444444          4444444
//     44444444                           44444444444444444444444444444        4444
//   4444444444                           44444444444444444444444444444         444
//  444444444444                         444444444444444444444444444444   444   444
//  44444444444444                                      444444444         44444
// 44444  44444444444         444                       44444444         444444
// 44444  4444444444      4444444444      444444        44444444    444444444444
//  444444444444444      4444  444444    4444444       44444444     444444444444
//  444444444444444     444    444444     444444       44444444      44444444444
//   4444444444444     4444   444444        4444                      4444444444
//    444444444444      4     44444         4444                       444444444
//     44444444444           444444         444                        44444444
//      44444444            444444         4444                         4444444
//                          44444          444                          44444
//                          44444         444      4                    4444
//                          44444        444      44                   444
//                          44444       444      4444
//                           444444  44444        444
//                             444444444           444
//                                                  44444   444
//                                                      444

/// @title PoolManager
/// @notice Holds the state for all pools
contract PoolManager is IPoolManager, ProtocolFees, NoDelegateCall, ERC6909Claims, Extsload, Exttload {
    using PoolIdLibrary for PoolKey;
    using SafeCast for *;
    using Pool for *;
    using Hooks for IHooks;
    using Position for mapping(bytes32 => Position.Info);
    using CurrencyDelta for Currency;
    using LPFeeLibrary for uint24;
    using Reserves for Currency;
    using CustomRevert for bytes4;

    /// @inheritdoc IPoolManager
    int24 public constant MAX_TICK_SPACING = TickMath.MAX_TICK_SPACING;

    /// @inheritdoc IPoolManager
    int24 public constant MIN_TICK_SPACING = TickMath.MIN_TICK_SPACING;

    mapping(PoolId id => Pool.State) internal _pools;

    constructor(uint256 controllerGasLimit) ProtocolFees(controllerGasLimit) {}

    /// @notice This will revert if the contract is locked
    modifier onlyWhenUnlocked() {
        if (!Lock.isUnlocked()) ManagerLocked.selector.revertWith();
        _;
    }

    /// @inheritdoc IPoolManager
    function unlock(bytes calldata data) external override noDelegateCall returns (bytes memory result) {
        if (Lock.isUnlocked()) AlreadyUnlocked.selector.revertWith();

        Lock.unlock();

        // the caller does everything in this callback, including paying what they owe via calls to settle
        result = IUnlockCallback(msg.sender).unlockCallback(data);

        if (NonZeroDeltaCount.read() != 0) CurrencyNotSettled.selector.revertWith();
        Lock.lock();
    }

    /// @inheritdoc IPoolManager
    function initialize(PoolKey memory key, uint160 sqrtPriceX96, bytes calldata hookData)
        external
        override
        noDelegateCall
        returns (int24 tick)
    {
        // see TickBitmap.sol for overflow conditions that can arise from tick spacing being too large
        if (key.tickSpacing > MAX_TICK_SPACING) TickSpacingTooLarge.selector.revertWith();
        if (key.tickSpacing < MIN_TICK_SPACING) TickSpacingTooSmall.selector.revertWith();
        if (key.currency0 >= key.currency1) CurrenciesOutOfOrderOrEqual.selector.revertWith();
        if (!key.hooks.isValidHookAddress(key.fee)) Hooks.HookAddressNotValid.selector.revertWith(address(key.hooks));

        uint24 lpFee = key.fee.getInitialLPFee();

        key.hooks.beforeInitialize(key, sqrtPriceX96, hookData);

        PoolId id = key.toId();
        (, uint24 protocolFee) = _fetchProtocolFee(key);

        tick = _pools[id].initialize(sqrtPriceX96, protocolFee, lpFee);

        key.hooks.afterInitialize(key, sqrtPriceX96, tick, hookData);

        // emit all details of a pool key. poolkeys are not saved in storage and must always be provided by the caller
        // the key's fee may be a static fee or a sentinel to denote a dynamic fee.
        emit Initialize(id, key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks);
    }

    /// @inheritdoc IPoolManager
    function modifyLiquidity(
        PoolKey memory key,
        IPoolManager.ModifyLiquidityParams memory params,
        bytes calldata hookData
    ) external override onlyWhenUnlocked returns (BalanceDeltas callerDeltas, BalanceDeltas feesAccrued) {
        PoolId id = key.toId();
        Pool.State storage pool = _getPool(id);
        pool.checkPoolInitialized();

        key.hooks.beforeModifyLiquidity(key, params, hookData);

        BalanceDeltas principalDeltas;
        (principalDeltas, feesAccrued) = pool.modifyLiquidity(
            Pool.ModifyLiquidityParams({
                owner: msg.sender,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: params.liquidityDelta.toInt128(),
                tickSpacing: key.tickSpacing,
                salt: params.salt
            })
        );

        callerDeltas = principalDeltas + feesAccrued;

        // event is emitted before the afterModifyLiquidity call to ensure events are always emitted in order
        emit ModifyLiquidity(id, msg.sender, params.tickLower, params.tickUpper, params.liquidityDelta);

        BalanceDeltas hookDeltas;
        (callerDeltas, hookDeltas) = key.hooks.afterModifyLiquidity(key, params, callerDeltas, hookData);

        // if the hook doesnt have the flag to be able to return deltas, hookDeltas will always be 0
        if (hookDeltas != BalanceDeltasLibrary.ZERO_DELTAS) {
            _accountPoolBalanceDeltas(key, hookDeltas, address(key.hooks));
        }

        _accountPoolBalanceDeltas(key, callerDeltas, msg.sender);
    }

    /// @inheritdoc IPoolManager
    function swap(PoolKey memory key, IPoolManager.SwapParams memory params, bytes calldata hookData)
        external
        override
        onlyWhenUnlocked
        returns (BalanceDeltas swapDeltas)
    {
        if (params.amountSpecified == 0) SwapAmountCannotBeZero.selector.revertWith();
        PoolId id = key.toId();
        Pool.State storage pool = _getPool(id);
        pool.checkPoolInitialized();

        BeforeSwapDeltas beforeSwapDeltas;
        {
            int256 amountToSwap;
            uint24 lpFeeOverride;
            (amountToSwap, beforeSwapDeltas, lpFeeOverride) = key.hooks.beforeSwap(key, params, hookData);

            // execute swap, account protocol fees, and emit swap event
            // _swap is needed to avoid stack too deep error
            swapDeltas = _swap(
                pool,
                id,
                Pool.SwapParams({
                    tickSpacing: key.tickSpacing,
                    zeroForOne: params.zeroForOne,
                    amountSpecified: amountToSwap,
                    sqrtPriceLimitX96: params.sqrtPriceLimitX96,
                    lpFeeOverride: lpFeeOverride
                }),
                params.zeroForOne ? key.currency0 : key.currency1 // input token
            );
        }

        BalanceDeltas hookDeltas;
        (swapDeltas, hookDeltas) = key.hooks.afterSwap(key, params, swapDeltas, hookData, beforeSwapDeltas);

        // if the hook doesnt have the flag to be able to return deltas, hookDeltas will always be 0
        if (hookDeltas != BalanceDeltasLibrary.ZERO_DELTAS) {
            _accountPoolBalanceDeltas(key, hookDeltas, address(key.hooks));
        }

        _accountPoolBalanceDeltas(key, swapDeltas, msg.sender);
    }

    /// @notice Internal swap function to execute a swap, take protocol fees on input token, and emit the swap event
    function _swap(Pool.State storage pool, PoolId id, Pool.SwapParams memory params, Currency inputCurrency)
        internal
        returns (BalanceDeltas)
    {
        (BalanceDeltas deltas, uint256 feeForProtocol, uint24 swapFee, Pool.SwapState memory state) = pool.swap(params);

        // the fee is on the input currency
        if (feeForProtocol > 0) _updateProtocolFees(inputCurrency, feeForProtocol);

        // event is emitted before the afterSwap call to ensure events are always emitted in order
        emit Swap(
            id, msg.sender, deltas.amount0(), deltas.amount1(), state.sqrtPriceX96, state.liquidity, state.tick, swapFee
        );

        return deltas;
    }

    /// @inheritdoc IPoolManager
    function donate(PoolKey memory key, uint256 amount0, uint256 amount1, bytes calldata hookData)
        external
        override
        onlyWhenUnlocked
        returns (BalanceDeltas deltas)
    {
        Pool.State storage pool = _getPool(key.toId());
        pool.checkPoolInitialized();

        key.hooks.beforeDonate(key, amount0, amount1, hookData);

        deltas = pool.donate(amount0, amount1);

        _accountPoolBalanceDeltas(key, deltas, msg.sender);

        key.hooks.afterDonate(key, amount0, amount1, hookData);
    }

    /// @inheritdoc IPoolManager
    function sync(Currency currency) public returns (uint256 balance) {
        balance = currency.balanceOfSelf();
        currency.setReserves(balance);
    }

    /// @inheritdoc IPoolManager
    function take(Currency currency, address to, uint256 amount) external override onlyWhenUnlocked {
        unchecked {
            // negation must be safe as amount is not negative
            _accountDelta(currency, -(amount.toInt128()), msg.sender);
            currency.transfer(to, amount);
        }
    }

    /// @inheritdoc IPoolManager
    function settle(Currency currency) external payable override onlyWhenUnlocked returns (uint256 paid) {
        if (currency.isNative()) {
            paid = msg.value;
        } else {
            if (msg.value > 0) NonZeroNativeValue.selector.revertWith();
            uint256 reservesBefore = currency.getReserves();
            uint256 reservesNow = sync(currency);
            paid = reservesNow - reservesBefore;
        }

        _accountDelta(currency, paid.toInt128(), msg.sender);
    }

    /// @inheritdoc IPoolManager
    function mint(address to, uint256 id, uint256 amount) external override onlyWhenUnlocked {
        unchecked {
            // negation must be safe as amount is not negative
            _accountDelta(CurrencyLibrary.fromId(id), -(amount.toInt128()), msg.sender);
            _mint(to, id, amount);
        }
    }

    /// @inheritdoc IPoolManager
    function burn(address from, uint256 id, uint256 amount) external override onlyWhenUnlocked {
        _accountDelta(CurrencyLibrary.fromId(id), amount.toInt128(), msg.sender);
        _burnFrom(from, id, amount);
    }

    /// @inheritdoc IPoolManager
    function updateDynamicLPFee(PoolKey memory key, uint24 newDynamicLPFee) external {
        if (!key.fee.isDynamicFee() || msg.sender != address(key.hooks)) {
            UnauthorizedDynamicLPFeeUpdate.selector.revertWith();
        }
        newDynamicLPFee.validate();
        PoolId id = key.toId();
        _pools[id].setLPFee(newDynamicLPFee);
    }

    /// @notice Adds a balance delta in a currency for a target address
    function _accountDelta(Currency currency, int128 delta, address target) internal {
        if (delta == 0) return;

        int256 current = currency.getDelta(target);
        int256 next = current + delta;

        if (next == 0) {
            NonZeroDeltaCount.decrement();
        } else if (current == 0) {
            NonZeroDeltaCount.increment();
        }

        currency.setDelta(target, next);
    }

    /// @notice Accounts the deltas of 2 currencies to a target address
    function _accountPoolBalanceDeltas(PoolKey memory key, BalanceDeltas deltas, address target) internal {
        _accountDelta(key.currency0, deltas.amount0(), target);
        _accountDelta(key.currency1, deltas.amount1(), target);
    }

    /// @notice Implementation of the _getPool function defined in ProtocolFees
    function _getPool(PoolId id) internal view override returns (Pool.State storage) {
        return _pools[id];
    }
}
