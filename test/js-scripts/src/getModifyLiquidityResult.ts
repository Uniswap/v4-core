import { BigNumber, ethers } from "ethers";
import JSBI from "jsbi";
import Decimal from "decimal.js";

import { getSqrtPriceAtTick, getAmount0Delta, getAmount1Delta, JSBI_ZERO } from "./utils/shared";

const params = process.argv[2].split(",");

const tickLower = params[0];
const tickUpper = params[1];
const liquidity = params[2];
const slot0Tick = params[3];
const slot0Price = params[4];

const result = modifyLiquidity(tickLower, tickUpper, liquidity, slot0Tick, slot0Price);
process.stdout.write(ethers.utils.defaultAbiCoder.encode(["int128[]"], [result]));

function modifyLiquidity(
  _tickLower: string,
  _tickUpper: string,
  _liquidity: string,
  slot0Tick: string,
  slot0Price: string,
): string[] {
  // TODO: Implement fee delta calculations.

  const liquidity = JSBI.BigInt(_liquidity);

  if (JSBI.EQ(liquidity, 0)) {
    return [JSBI_ZERO.toString(), JSBI_ZERO.toString()];
  }

  // State values in slot0.
  const tick = JSBI.BigInt(slot0Tick);
  const sqrtPriceX96 = JSBI.BigInt(slot0Price);

  // Position lower and upper ticks.
  const tickLower = JSBI.BigInt(_tickLower);
  const tickUpper = JSBI.BigInt(_tickUpper);

  let delta: string[] = [];

  if (JSBI.LT(tick, tickLower)) {
    // The current tick is less than the lowest tick of the position, so the position is entirely in token0.
    let priceLower = JSBI.BigInt(getSqrtPriceAtTick(_tickLower));
    let priceUpper = JSBI.BigInt(getSqrtPriceAtTick(_tickUpper));
    let amount0 = getAmount0Delta(priceLower, priceUpper, liquidity);
    delta.push(amount0.toString());
    delta.push(JSBI_ZERO.toString());
  } else if (JSBI.LT(tick, tickUpper)) {
    // In-range liquidity. As we are just calculating the values of the delta.
    // We do not update any global state variable for state.liquidity, but note that the protocol increments state liquidity in this case.

    let priceUpper = JSBI.BigInt(getSqrtPriceAtTick(_tickUpper));
    let priceLower = JSBI.BigInt(getSqrtPriceAtTick(_tickLower));

    // When tickLower == the current tick, the price returned from getSqrtPriceATick has a slight error in JS.
    // In solidity because the calculations for getSqrtRatioAtTick(tickLower) == currentSqrtPriceX96, the
    // numerator becomes 0, and the amount becomes 0.
    // So instead of using the price from getSqrtRatioAtTick, we set the priceLower to the current price.
    if (JSBI.EQ(tickLower, tick)) {
      priceLower = sqrtPriceX96;
    }

    let amount0 = getAmount0Delta(sqrtPriceX96, priceUpper, liquidity);
    let amount1 = getAmount1Delta(priceLower, sqrtPriceX96, liquidity);

    delta.push(amount0.toString());
    delta.push(amount1.toString());
  } else {
    // The current tick is greater than the highest tick of the position, meaning the position is entirely in token1.
    let priceLower = JSBI.BigInt(getSqrtPriceAtTick(_tickLower));
    let priceUpper = JSBI.BigInt(getSqrtPriceAtTick(_tickUpper));

    let amount1 = getAmount1Delta(priceLower, priceUpper, liquidity);
    delta.push(JSBI_ZERO.toString());
    delta.push(amount1.toString());
  }

  return delta;
}
