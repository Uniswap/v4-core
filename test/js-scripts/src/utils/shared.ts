import Decimal from "decimal.js";
import JSBI from "jsbi";
import { SqrtPriceMath } from "@uniswap/v3-sdk";

export const JSBI_ZERO = JSBI.BigInt(0);

export function getSqrtPriceAtTick(tick: string): string {
  return new Decimal(1.0001).pow(tick).sqrt().mul(new Decimal(2).pow(96)).toFixed(0);
}

export function getAmount0Delta(sqrtPriceAX96: JSBI, sqrtPriceBX96: JSBI, liquidity: JSBI): JSBI {
  if (JSBI.lessThan(liquidity, JSBI_ZERO)) {
    return SqrtPriceMath.getAmount0Delta(sqrtPriceAX96, sqrtPriceBX96, JSBI.unaryMinus(liquidity), false);
  } else {
    return JSBI.unaryMinus(SqrtPriceMath.getAmount0Delta(sqrtPriceAX96, sqrtPriceBX96, liquidity, true));
  }
}

export function getAmount1Delta(sqrtPriceAX96: JSBI, sqrtPriceBX96: JSBI, liquidity: JSBI): JSBI {
  if (JSBI.lessThan(liquidity, JSBI_ZERO)) {
    return SqrtPriceMath.getAmount1Delta(sqrtPriceAX96, sqrtPriceBX96, JSBI.unaryMinus(liquidity), false);
  } else {
    return JSBI.unaryMinus(SqrtPriceMath.getAmount1Delta(sqrtPriceAX96, sqrtPriceBX96, liquidity, true));
  }
}
