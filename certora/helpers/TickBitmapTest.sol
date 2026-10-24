// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { TickBitmap, BitMath } from "src/libraries/TickBitmap.sol";

contract TickBitmapTest {
    using TickBitmap for mapping(int16 => uint256);

    /// @dev The minimum tick that may be passed to #getSqrtPriceAtTick computed from log base 1.0001 of 2**-128
    int24 internal constant MIN_TICK = -887272;
    /// @dev The maximum tick that may be passed to #getSqrtPriceAtTick computed from log base 1.0001 of 2**128
    int24 internal constant MAX_TICK = 887272;

    /// @dev The minimum tick spacing value drawn from the range of type int16 that is greater than 0, i.e. min from the range [1, 32767]
    int24 internal constant MIN_TICK_SPACING = 1;
    /// @dev The maximum tick spacing value drawn from the range of type int16, i.e. max from the range [1, 32767]
    int24 internal constant MAX_TICK_SPACING = type(int16).max;

    int24 public tick0;
    int24 public tick1;
    int24 public tickSpacing0;
    mapping(int16 => uint256) public bitmap;

    int24 public nextTick; 
    bool public nextInitialized;
    int24 public compressed;
    int16 public wordPos;
    uint8 public bitPos;

    function nextToTick0Diff() public view returns (int256) {
        return int256(nextTick) - int256(tick0);
    }

    function isAtLeastOneWord(bool lte) public view returns (bool) {
        return (lte ? tick0 >= -8388352 : tick0 < 8388351);
    }

    function isValidTick() public view returns (bool) {
        return tick0 >= MIN_TICK && tick0 <= MAX_TICK;
    }

    function isValidTickSpacing() public view returns (bool) {
        return tickSpacing0 >= MIN_TICK_SPACING && tickSpacing0 <= MAX_TICK_SPACING;
    }

    function setTick0(uint24 absTick, bool isNegative) public {
        require (absTick <= uint24(MAX_TICK));
        tick0 = isNegative ? -int24(absTick) : int24(absTick);
    }

    function setTickSpacing0(uint24 tickSpacing) public {
        require (tickSpacing >= uint24(MIN_TICK_SPACING) && tickSpacing <= uint24(MAX_TICK_SPACING));
        tickSpacing0 = int24(tickSpacing);
    }

    function flipTick() external {
        bitmap.flipTick(tick0, tickSpacing0);
    }

    function flipTickSol() public {
        if (tick0 % tickSpacing0 != 0) revert TickBitmap.TickMisaligned(tick0, tickSpacing0);
        (int16 _wordPos, uint8 _bitPos) = TickBitmap.position(tick0 / tickSpacing0);
        uint256 mask = 1 << _bitPos;
        bitmap[_wordPos] ^= mask; 
    }

    function compress() public {
        compressed = TickBitmap.compress(tick0, tickSpacing0);
    }

    function compressSol() public {
        compressed = tick0 / tickSpacing0;
        if (tick0 < 0 && tick0 % tickSpacing0 != 0) compressed--;
    }

    function position() public {
        (wordPos, bitPos) = TickBitmap.position(compressed);
    }

    function positionSol() public {
        wordPos = int16(compressed >> 8);
        bitPos = uint8(uint24(compressed % 256));
    }

    function getBitPos(bool lte) public view returns (uint8) {
        (int16 wordPos_, uint8 bitPos_) = TickBitmap.position(
            TickBitmap.compress(tick0, tickSpacing0) + (lte ? int24(0) : int24(1))
        );
        return bitPos_;
    }

    function getBitPosNext() public view returns (uint8) {
        (int16 wordPos_, uint8 bitPos_) = TickBitmap.position(nextTick / tickSpacing0);
        return bitPos_;
    }

    function getBitMapAtWord(bool lte) public view returns (uint256) {
        (int16 wordPos_, ) = TickBitmap.position(
            TickBitmap.compress(tick0, tickSpacing0) + (lte ? int24(0) : int24(1))
        );
        return bitmap[wordPos_];
    }

    function getBitPosMask(bool lte, uint8 bitPos) public pure returns (uint256) {
        unchecked {
            return lte 
            ? type(uint256).max >> (uint256(type(uint8).max) - bitPos)
            : ~((1 << bitPos) - 1);
        }
    }

    function setNextInitializedTickWithinOneWord(bool lte) external {
        (nextTick, nextInitialized) = bitmap.nextInitializedTickWithinOneWord(tick0, tickSpacing0, lte);
    }

    function isInitialized0() public view returns (bool) {
        unchecked {
            if ((tick0/ tickSpacing0)*tickSpacing0 != tick0) return false;
            (int16 _wordPos, uint8 _bitPos) = TickBitmap.position(tick0 / tickSpacing0);
            return bitmap[_wordPos] & (1 << _bitPos) != 0;
        }
    }

    function isInitialized1() public view returns (bool) {
        unchecked {
            if ((tick1 / tickSpacing0)*tickSpacing0 != tick1) return false;
            (int16 _wordPos, uint8 _bitPos) = TickBitmap.position(tick1 / tickSpacing0);
            return bitmap[_wordPos] & (1 << _bitPos) != 0;
        }
    }

    function isNextInitialized() public view returns (bool) {
        unchecked {
            if ((nextTick / tickSpacing0)*tickSpacing0 != nextTick) return false;
            (int16 _wordPos, uint8 _bitPos) = TickBitmap.position(nextTick / tickSpacing0);
            return bitmap[_wordPos] & (1 << _bitPos) != 0;
        }
    }

    function tick1BetweenNextAndCurrent(bool lte) public view returns (bool) {
        return lte
            ? (tick1 > nextTick && tick1 <= tick0) 
            : (tick1 < nextTick && tick1 > tick0);
    }

    function nextTickGTTick() public view returns (bool) {
        return nextTick > tick0;
    }

    function differentTicks01() public view returns (bool) {
        return (tick0 != tick1 && tickSpacing0 > 0);
    }

    function getLSB(uint256 x) external pure returns (uint8) {
        return BitMath.leastSignificantBit(x);
    }
}
