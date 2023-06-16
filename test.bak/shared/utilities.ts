import bn from 'bignumber.js'
import { BigNumber, BigNumberish, Contract, ContractTransaction, utils, Wallet } from 'ethers'
import { ethers } from 'hardhat'

export const MaxUint128 = BigNumber.from(2).pow(128).sub(1)

export const getMinTick = (tickSpacing: number) => Math.ceil(-887272 / tickSpacing) * tickSpacing
export const getMaxTick = (tickSpacing: number) => Math.floor(887272 / tickSpacing) * tickSpacing

export const MIN_SQRT_RATIO = BigNumber.from('4295128739')
export const MAX_SQRT_RATIO = BigNumber.from('1461446703485210103287273052203988822378723970342')

export enum FeeAmount {
  LOW = 500,
  MEDIUM = 3000,
  HIGH = 10000,
}

export const TICK_SPACINGS: { [amount in FeeAmount]: number } = {
  [FeeAmount.LOW]: 10,
  [FeeAmount.MEDIUM]: 60,
  [FeeAmount.HIGH]: 200,
}

export function expandTo18Decimals(n: number): BigNumber {
  return BigNumber.from(n).mul(BigNumber.from(10).pow(18))
}

bn.config({ EXPONENTIAL_AT: 999999, DECIMAL_PLACES: 40 })

// returns the sqrt price as a 64x96
export function encodeSqrtPriceX96(reserve1: BigNumberish, reserve0: BigNumberish): BigNumber {
  return BigNumber.from(
    new bn(reserve1.toString())
      .div(reserve0.toString())
      .sqrt()
      .multipliedBy(new bn(2).pow(96))
      .integerValue(3)
      .toString()
  )
}

export function getPositionKey(address: string, lowerTick: number, upperTick: number): string {
  return utils.keccak256(utils.solidityPack(['address', 'int24', 'int24'], [address, lowerTick, upperTick]))
}

export function getPoolId({
  currency0,
  currency1,
  fee,
  tickSpacing,
  hooks,
}: {
  currency0: string | Contract
  currency1: string | Contract
  fee: number
  tickSpacing: number
  hooks: string | Contract
}): string {
  return utils.keccak256(
    utils.defaultAbiCoder.encode(
      ['address', 'address', 'uint24', 'int24', 'address'],
      [
        typeof currency0 === 'string' ? currency0 : currency0.address,
        typeof currency1 === 'string' ? currency1 : currency1.address,
        fee,
        tickSpacing,
        typeof hooks === 'string' ? hooks : hooks.address,
      ]
    )
  )
}

export type SwapFunction = (
  amount: BigNumberish,
  to: Wallet | string,
  sqrtPriceLimitX96?: BigNumberish
) => Promise<ContractTransaction>
export type SwapToPriceFunction = (sqrtPriceX96: BigNumberish, to: Wallet | string) => Promise<ContractTransaction>
export type ModifyPositionFunction = (
  tickLower: BigNumberish,
  tickUpper: BigNumberish,
  liquidityDelta: BigNumberish
) => Promise<ContractTransaction>
export type DonateFunction = (amount0: BigNumberish, amount1: BigNumberish) => Promise<ContractTransaction>

interface HookMask {
  beforeInitialize: boolean
  afterInitialize: boolean
  beforeModifyPosition: boolean
  afterModifyPosition: boolean
  beforeSwap: boolean
  afterSwap: boolean
  beforeDonate: boolean
  afterDonate: boolean
}

/**
 * Creates a 20 byte mask for the given hook configuration
 */
export function createHookMask({
  beforeInitialize,
  afterInitialize,
  beforeModifyPosition,
  afterModifyPosition,
  beforeSwap,
  afterSwap,
  beforeDonate,
  afterDonate,
}: HookMask): string {
  let result: BigNumber = BigNumber.from(0)
  if (beforeInitialize) result = result.add(BigNumber.from(1).shl(159))
  if (afterInitialize) result = result.add(BigNumber.from(1).shl(158))
  if (beforeModifyPosition) result = result.add(BigNumber.from(1).shl(157))
  if (afterModifyPosition) result = result.add(BigNumber.from(1).shl(156))
  if (beforeSwap) result = result.add(BigNumber.from(1).shl(155))
  if (afterSwap) result = result.add(BigNumber.from(1).shl(154))
  if (beforeDonate) result = result.add(BigNumber.from(1).shl(153))
  if (afterDonate) result = result.add(BigNumber.from(1).shl(152))
  return utils.hexZeroPad(result.toHexString(), 20)
}

/**
 * Returns a wallet whose first transaction will create a contract satisfying the leading
 * bytes required by hookMask. If provided, the mnemonic argument short-circuits our search
 * to save time.
 */
export function getWalletForDeployingHookMask(hookMask: HookMask, mnemonic?: string): [Wallet, string] {
  const startingString = createHookMask(hookMask).slice(0, 4)
  let wallet: Wallet = mnemonic ? ethers.Wallet.fromMnemonic(mnemonic) : ethers.Wallet.createRandom()
  let contractAddress: string | undefined

  while (contractAddress === undefined) {
    const prospectiveContractAddress = utils.getContractAddress({ from: wallet.address, nonce: 0 })
    if (prospectiveContractAddress.slice(0, 4).toLowerCase() === startingString) {
      contractAddress = prospectiveContractAddress
    } else {
      // if, for whatever reason, we generate a bad address but a mnemonic was provided,
      // it's stale and we surface the error
      if (mnemonic) throw Error('Stale mnemonic')
      wallet = ethers.Wallet.createRandom()
    }
  }

  return [wallet, contractAddress]
}
