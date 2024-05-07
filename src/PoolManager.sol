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
import {BalanceDelta, BalanceDeltaLibrary} from "./types/BalanceDelta.sol";
import {Lock} from "./libraries/Lock.sol";
import {CurrencyDelta} from "./libraries/CurrencyDelta.sol";
import {NonZeroDeltaCount} from "./libraries/NonZeroDeltaCount.sol";
import {PoolGetters} from "./libraries/PoolGetters.sol";
import {Reserves} from "./libraries/Reserves.sol";
import {Extsload} from "./Extsload.sol";

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
/// @notice Holds the state for all pools
contract PoolManager is IPoolManager, ProtocolFees, NoDelegateCall, ERC6909Claims, Extsload {
    using PoolIdLibrary for PoolKey;
    using SafeCast for *;
    using Pool for *;
    using Hooks for IHooks;
    using Position for mapping(bytes32 => Position.Info);
    using CurrencyLibrary for Currency;
    using CurrencyDelta for Currency;
    using LPFeeLibrary for uint24;
    using PoolGetters for Pool.State;
    using Reserves for Currency;

    /// @inheritdoc IPoolManager
    int24 public constant MAX_TICK_SPACING = TickMath.MAX_TICK_SPACING;

    /// @inheritdoc IPoolManager
    int24 public constant MIN_TICK_SPACING = TickMath.MIN_TICK_SPACING;

    mapping(PoolId id => Pool.State) public pools;

    constructor(uint256 controllerGasLimit) ProtocolFees(controllerGasLimit) {}

    function _getPool(PoolId id) internal view override returns (Pool.State storage) {
        return pools[id];
    }

    /// @inheritdoc IPoolManager
    function getSlot0(PoolId id)
        external
        view
        override
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee)
    {
        Pool.Slot0 memory slot0 = pools[id].slot0;

        return (slot0.sqrtPriceX96, slot0.tick, slot0.protocolFee, slot0.lpFee);
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
        return currency.getDelta(caller);
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
        noDelegateCall
        returns (int24 tick)
    {
        // see TickBitmap.sol for overflow conditions that can arise from tick spacing being too large
        if (key.tickSpacing > MAX_TICK_SPACING) revert TickSpacingTooLarge();
        if (key.tickSpacing < MIN_TICK_SPACING) revert TickSpacingTooSmall();
        if (key.currency0 >= key.currency1) revert CurrenciesOutOfOrderOrEqual();
        if (!key.hooks.isValidHookAddress(key.fee)) revert Hooks.HookAddressNotValid(address(key.hooks));

        uint24 lpFee = key.fee.getInitialLPFee();

        key.hooks.beforeInitialize(key, sqrtPriceX96, hookData);

        PoolId id = key.toId();
        (, uint24 protocolFee) = _fetchProtocolFee(key);

        tick = pools[id].initialize(sqrtPriceX96, protocolFee, lpFee);

        key.hooks.afterInitialize(key, sqrtPriceX96, tick, hookData);

        // On intitalize we emit the key's fee, which tells us all fee settings a pool can have: either a static swap fee or dynamic swap fee and if the hook has enabled swap or withdraw fees.
        emit Initialize(id, key.currency0, key.currency1, key.fee, key.tickSpacing, key.hooks);
    }

    /// @inheritdoc IPoolManager
    function unlock(bytes calldata data) external override noDelegateCall returns (bytes memory result) {
        if (Lock.isUnlocked()) revert AlreadyUnlocked();

        Lock.unlock();

        // the caller does everything in this callback, including paying what they owe via calls to settle
        result = IUnlockCallback(msg.sender).unlockCallback(data);

        if (NonZeroDeltaCount.read() != 0) revert CurrencyNotSettled();
        Lock.lock();
    }

    /// @inheritdoc IPoolManager
    function sync(Currency currency) public returns (uint256 balance) {
        balance = currency.balanceOfSelf();
        currency.setReserves(balance);
    }

    function _accountDelta(Currency currency, int128 delta) internal {
        if (delta == 0) return;

        int256 current = currency.getDelta(msg.sender);
        int256 next = current + delta;

        if (next == 0) {
            NonZeroDeltaCount.decrement();
        } else if (current == 0) {
            NonZeroDeltaCount.increment();
        }

        currency.setDelta(msg.sender, next);
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
    ) external override onlyWhenUnlocked returns (BalanceDelta delta, BalanceDelta feeDelta) {
        PoolId id = key.toId();
        _checkPoolInitialized(id);

        key.hooks.beforeModifyLiquidity(key, params, hookData);

        (delta, feeDelta) = pools[id].modifyLiquidity(
            Pool.ModifyLiquidityParams({
                owner: msg.sender,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: params.liquidityDelta.toInt128(),
                tickSpacing: key.tickSpacing
            })
        );

        _accountPoolBalanceDelta(key, delta + feeDelta);

        emit ModifyLiquidity(id, msg.sender, params.tickLower, params.tickUpper, params.liquidityDelta);

        key.hooks.afterModifyLiquidity(key, params, delta, hookData);
    }

    /// @inheritdoc IPoolManager
    function swap(PoolKey memory key, IPoolManager.SwapParams memory params, bytes calldata hookData)
        external
        override
        onlyWhenUnlocked
        returns (BalanceDelta)
    {
        PoolId id = key.toId();
        _checkPoolInitialized(id);

        key.hooks.beforeSwap(key, params, hookData);

        (BalanceDelta delta, uint256 feeForProtocol, uint24 swapFee, Pool.SwapState memory state) = pools[id].swap(
            Pool.SwapParams({
                tickSpacing: key.tickSpacing,
                zeroForOne: params.zeroForOne,
                amountSpecified: params.amountSpecified,
                sqrtPriceLimitX96: params.sqrtPriceLimitX96
            })
        );

        _accountPoolBalanceDelta(key, delta);

        // The fee is on the input currency.
        if (feeForProtocol > 0) {
            _updateProtocolFees(params.zeroForOne ? key.currency0 : key.currency1, feeForProtocol);
        }

        emit Swap(
            id, msg.sender, delta.amount0(), delta.amount1(), state.sqrtPriceX96, state.liquidity, state.tick, swapFee
        );

        key.hooks.afterSwap(key, params, delta, hookData);

        return delta;
    }

    /// @inheritdoc IPoolManager
    function donate(PoolKey memory key, uint256 amount0, uint256 amount1, bytes calldata hookData)
        external
        override
        onlyWhenUnlocked
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
    function take(Currency currency, address to, uint256 amount) external override onlyWhenUnlocked {
        unchecked {
            // subtraction must be safe
            _accountDelta(currency, -(amount.toInt128()));
            currency.transfer(to, amount);
        }
    }

    /// @inheritdoc IPoolManager
    function settle(Currency currency) external payable override onlyWhenUnlocked returns (uint256 paid) {
        if (currency.isNative()) {
            paid = msg.value;
        } else {
            if (msg.value > 0) revert NonZeroNativeValue();
            uint256 reservesBefore = currency.getReserves();
            uint256 reservesNow = sync(currency);
            paid = reservesNow - reservesBefore;
        }
        _accountDelta(currency, paid.toInt128());
    }

    /// @inheritdoc IPoolManager
    function mint(address to, uint256 id, uint256 amount) external override onlyWhenUnlocked {
        unchecked {
            // subtraction must be safe
            _accountDelta(CurrencyLibrary.fromId(id), -(amount.toInt128()));
            _mint(to, id, amount);
        }
    }

    /// @inheritdoc IPoolManager
    function burn(address from, uint256 id, uint256 amount) external override onlyWhenUnlocked {
        _accountDelta(CurrencyLibrary.fromId(id), amount.toInt128());
        _burnFrom(from, id, amount);
    }

    function updateDynamicLPFee(PoolKey memory key, uint24 newDynamicLPFee) external {
        if (!key.fee.isDynamicFee() || msg.sender != address(key.hooks)) revert UnauthorizedDynamicLPFeeUpdate();
        newDynamicLPFee.validate();
        PoolId id = key.toId();
        pools[id].setLPFee(newDynamicLPFee);
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

    /// @notice Temporary view function. Replaceable by transient EXTSLOAD.
    function getReserves(Currency currency) external view returns (uint256 balance) {
        return currency.getReserves();
    }

    function getFeeGrowthGlobals(PoolId id)
        external
        view
        returns (uint256 feeGrowthGlobal0x128, uint256 feeGrowthGlobal1x128)
    {
        return pools[id].getFeeGrowthGlobals();
    }
}
