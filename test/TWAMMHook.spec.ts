import { createFixtureLoader } from 'ethereum-waffle'
import { BigNumber, Wallet } from 'ethers'
import hre, { ethers } from 'hardhat'
import snapshotGasCost from '@uniswap/snapshot-gas-cost'
import { TWAMMHook, PoolManager, PoolModifyPositionTest, PoolSwapTest, TestERC20 } from '../typechain'
import { MAX_TICK_SPACING } from './shared/constants'
import { expect } from './shared/expect'
import { tokensFixture } from './shared/fixtures'
import {
  createHookMask,
  encodeSqrtPriceX96,
  expandTo18Decimals,
  getMaxTick,
  getMinTick,
  getPoolId,
} from './shared/utilities'
import { inOneBlock } from './shared/inOneBlock'

function nIntervalsFrom(timestamp: number, interval: number, n: number): number {
  return timestamp + (interval - (timestamp % interval)) + interval * (n - 1)
}

type OrderKey = {
  owner: string
  expiration: number
  zeroForOne: boolean
}

type PoolKey = {
  token0: string
  token1: string
  fee: number
  tickSpacing: number
  hooks: string
}

// TODO: temporary hack for precision errors affecting token balances
const EXTRA_TOKENS = 20

describe('TWAMM Hook', () => {
  let wallets: Wallet[]
  let wallet: Wallet
  let twamm: TWAMMHook
  let poolManager: PoolManager
  let modifyPositionTest: PoolModifyPositionTest
  let token0: TestERC20
  let token1: TestERC20

  /**
   * We are using hardhat_setCode to deploy the twamm, so we need to replace all the immutable references
   * @param poolManagerAddress the address of the pool manager
   * @param expirationInterval the aexpiration interval
   */
  async function getDeployedTWAMMCode(poolManagerAddress: string, expirationInterval: number): Promise<string> {
    const artifact = await hre.artifacts.readArtifact('TWAMMHook')
    const fullyQualifiedName = `${artifact.sourceName}:${artifact.contractName}`
    const debugArtifact = await hre.artifacts.getBuildInfo(fullyQualifiedName)
    const immutableReferences =
      debugArtifact?.output?.contracts?.[artifact.sourceName]?.[artifact.contractName]?.evm?.deployedBytecode
        ?.immutableReferences
    if (!immutableReferences) throw new Error('Could not find immutable references')
    if (Object.keys(immutableReferences).length !== 2) throw new Error('Unexpected immutable references length')
    const addressRefs = immutableReferences[Object.keys(immutableReferences)[1]]
    const expirationRefs = immutableReferences[Object.keys(immutableReferences)[0]]
    let bytecode: string = artifact.deployedBytecode
    const paddedTo32Address = '0'.repeat(24) + poolManagerAddress.slice(2)
    const expirationHex = expirationInterval.toString(16)
    const paddedTo32Expiration = '0'.repeat(64 - expirationHex.length) + expirationHex
    for (const { start, length } of addressRefs) {
      if (length !== 32) throw new Error('Unexpected immutable reference length')
      bytecode = bytecode.slice(0, start * 2 + 2) + paddedTo32Address + bytecode.slice(2 + start * 2 + length * 2)
    }
    for (const { start, length } of expirationRefs) {
      if (length !== 32) throw new Error('Unexpected immutable reference length')
      bytecode = bytecode.slice(0, start * 2 + 2) + paddedTo32Expiration + bytecode.slice(2 + start * 2 + length * 2)
    }
    return bytecode
  }

  const fixture = async ([wallet]: Wallet[]) => {
    const twammFactory = await ethers.getContractFactory('TWAMMHook')

    const poolManagerFactory = await ethers.getContractFactory('PoolManager')
    const swapTestFactory = await ethers.getContractFactory('PoolSwapTest')
    const modifyPositionTestFactory = await ethers.getContractFactory('PoolModifyPositionTest')
    const tokens = await tokensFixture()
    const manager = (await poolManagerFactory.deploy()) as PoolManager

    const twammHookAddress = createHookMask({
      beforeInitialize: true,
      afterInitialize: false,
      beforeModifyPosition: true,
      afterModifyPosition: false,
      beforeSwap: true,
      afterSwap: false,
      beforeDonate: false,
      afterDonate: false,
    })

    await hre.network.provider.send('hardhat_setCode', [
      twammHookAddress,
      await getDeployedTWAMMCode(manager.address, 10_000),
    ])

    const twamm: TWAMMHook = twammFactory.attach(twammHookAddress) as TWAMMHook

    const swapTest = (await swapTestFactory.deploy(manager.address)) as PoolSwapTest
    const modifyPositionTest = (await modifyPositionTestFactory.deploy(manager.address)) as PoolModifyPositionTest

    for (const token of [tokens.token0, tokens.token1]) {
      // TODO: HACK!! send some extra tokens so that the current precision errors do not revert test tx's
      token.transfer(twamm.address, EXTRA_TOKENS)
      for (const spender of [swapTest, modifyPositionTest, twamm]) {
        await token.connect(wallet).approve(spender.address, ethers.constants.MaxUint256)
      }
    }

    return {
      manager,
      swapTest,
      modifyPositionTest,
      tokens,
      twamm,
    }
  }

  let loadFixture: ReturnType<typeof createFixtureLoader>
  before('create fixture loader', async () => {
    wallets = await (ethers as any).getSigners()
    wallet = wallets[0]

    loadFixture = createFixtureLoader(wallets)
  })

  let poolKey: {
    token0: string
    token1: string
    fee: number
    tickSpacing: number
    hooks: string
  }

  beforeEach('deploy twamm', async () => {
    ;({
      twamm,
      manager: poolManager,
      tokens: { token0, token1 },
      modifyPositionTest,
    } = await loadFixture(fixture))
    poolKey = {
      token0: token0.address,
      token1: token1.address,
      fee: 0,
      hooks: twamm.address,
      tickSpacing: MAX_TICK_SPACING,
    }
  })

  let snapshotId: string

  beforeEach('check the pool is not initialized', async () => {
    const { sqrtPriceX96 } = await poolManager.getSlot0(poolKey)
    expect(sqrtPriceX96, 'pool is not initialized').to.eq(0)
    // it seems like the waffle fixture is not working correctly (perhaps due to hardhat_setCode), and if we don't
    // do this and revert in afterEach, the pool is already initialized
    snapshotId = await hre.network.provider.send('evm_snapshot')
  })

  afterEach('revert', async () => {
    // see the beforeEach hook
    await hre.network.provider.send('evm_revert', [snapshotId])
  })

  describe('#beforeInitialize', async () => {
    it('initializes the twamm', async () => {
      expect(await twamm.lastVirtualOrderTimestamp(getPoolId(poolKey))).to.equal(0)
      await poolManager.initialize(poolKey, encodeSqrtPriceX96(1, 1))
      expect(await twamm.lastVirtualOrderTimestamp(getPoolId(poolKey))).to.equal(
        (await ethers.provider.getBlock('latest')).timestamp
      )
    })
  })

  describe('#executeTWAMMOrders', async () => {
    let poolKey: PoolKey
    let orderKey0: OrderKey
    let orderKey1: OrderKey
    let latestTimestamp: number
    let expiration: number

    beforeEach(async () => {
      latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
      expiration = nIntervalsFrom(latestTimestamp, 10_000, 3)

      poolKey = {
        token0: token0.address,
        token1: token1.address,
        fee: 0,
        hooks: twamm.address,
        tickSpacing: 10,
      }
      orderKey0 = {
        zeroForOne: true,
        owner: wallet.address,
        expiration,
      }
      orderKey1 = {
        zeroForOne: false,
        owner: wallet.address,
        expiration,
      }

      await ethers.provider.send('evm_setNextBlockTimestamp', [nIntervalsFrom(latestTimestamp, 10_000, 1)])
      await poolManager.initialize(poolKey, encodeSqrtPriceX96(1, 1))
      latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp

      await modifyPositionTest.modifyPosition(poolKey, {
        tickLower: getMinTick(10),
        tickUpper: getMaxTick(10),
        liquidityDelta: expandTo18Decimals(1),
      })
    })

    describe('when both order pools are selling', async () => {
      it('gas with no initialized ticks', async () => {
        await inOneBlock(latestTimestamp + 100, async () => {
          await twamm.submitLongTermOrder(poolKey, orderKey0, expandTo18Decimals(1))
          await twamm.submitLongTermOrder(poolKey, orderKey1, expandTo18Decimals(10))
        })
        await ethers.provider.send('evm_setNextBlockTimestamp', [latestTimestamp + 10_000])
        await snapshotGasCost(twamm.executeTWAMMOrders(poolKey))
      })

      it('gas crossing 1 initialized tick', async () => {
        await modifyPositionTest.modifyPosition(poolKey, {
          tickLower: -200,
          tickUpper: 200,
          liquidityDelta: expandTo18Decimals(1),
        })
        await inOneBlock(latestTimestamp + 100, async () => {
          await twamm.submitLongTermOrder(poolKey, orderKey0, expandTo18Decimals(1))
          await twamm.submitLongTermOrder(poolKey, orderKey1, expandTo18Decimals(10))
        })
        await ethers.provider.send('evm_setNextBlockTimestamp', [latestTimestamp + 10_000])
        await snapshotGasCost(twamm.executeTWAMMOrders(poolKey))
      })

      it('gas crossing 2 initialized ticks', async () => {
        await modifyPositionTest.modifyPosition(poolKey, {
          tickLower: -200,
          tickUpper: 200,
          liquidityDelta: expandTo18Decimals(1),
        })
        await modifyPositionTest.modifyPosition(poolKey, {
          tickLower: -2000,
          tickUpper: 2000,
          liquidityDelta: expandTo18Decimals(1),
        })

        await inOneBlock(latestTimestamp + 100, async () => {
          await twamm.submitLongTermOrder(poolKey, orderKey0, expandTo18Decimals(1))
          await twamm.submitLongTermOrder(poolKey, orderKey1, expandTo18Decimals(10))
        })

        await ethers.provider.send('evm_setNextBlockTimestamp', [latestTimestamp + 10_000])
        await snapshotGasCost(twamm.executeTWAMMOrders(poolKey))
      })
    })

    describe('when only one pool is selling', () => {
      beforeEach('set up pool', async () => {
        await modifyPositionTest.modifyPosition(poolKey, {
          tickLower: getMinTick(10),
          tickUpper: getMaxTick(10),
          liquidityDelta: expandTo18Decimals(10),
        })
      })

      it('gas crossing no initialized tick', async () => {
        await ethers.provider.send('evm_setNextBlockTimestamp', [latestTimestamp + 100])
        await twamm.submitLongTermOrder(poolKey, orderKey0, expandTo18Decimals(7))

        await ethers.provider.send('evm_setNextBlockTimestamp', [expiration + 300])
        await snapshotGasCost(twamm.executeTWAMMOrders(poolKey))
      })

      it('gas crossing 1 initialized tick', async () => {
        await modifyPositionTest.modifyPosition(poolKey, {
          tickLower: -2000,
          tickUpper: 2000,
          liquidityDelta: expandTo18Decimals(1),
        })

        await ethers.provider.send('evm_setNextBlockTimestamp', [latestTimestamp + 100])
        await twamm.submitLongTermOrder(poolKey, orderKey0, expandTo18Decimals(7))

        await ethers.provider.send('evm_setNextBlockTimestamp', [expiration + 300])
        await snapshotGasCost(twamm.executeTWAMMOrders(poolKey))
      })

      it('gas crossing 2 initialized ticks', async () => {
        await modifyPositionTest.modifyPosition(poolKey, {
          tickLower: -2000,
          tickUpper: 2000,
          liquidityDelta: expandTo18Decimals(1),
        })
        await modifyPositionTest.modifyPosition(poolKey, {
          tickLower: -3000,
          tickUpper: 3000,
          liquidityDelta: expandTo18Decimals(1),
        })

        await ethers.provider.send('evm_setNextBlockTimestamp', [latestTimestamp + 100])
        await twamm.submitLongTermOrder(poolKey, orderKey0, expandTo18Decimals(7))

        await ethers.provider.send('evm_setNextBlockTimestamp', [expiration + 300])
        await snapshotGasCost(twamm.executeTWAMMOrders(poolKey))
      })
    })
  })

  describe('end-to-end integration', () => {
    let start: number
    let expiration: number
    let key: any
    let orderKey0: OrderKey
    let orderKey1: OrderKey
    let liquidityBalance: BigNumber

    describe('when TWAMM crosses a tick', () => {
      beforeEach('set up pool', async () => {
        const latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
        const amountLiquidity = expandTo18Decimals(1)

        start = nIntervalsFrom(latestTimestamp, 10_000, 1)
        expiration = nIntervalsFrom(latestTimestamp, 10_000, 3)

        orderKey0 = {
          zeroForOne: true,
          owner: wallet.address,
          expiration,
        }
        orderKey1 = {
          zeroForOne: false,
          owner: wallet.address,
          expiration,
        }

        key = {
          token0: token0.address,
          token1: token1.address,
          fee: 0,
          hooks: twamm.address,
          tickSpacing: 10,
        }
        await poolManager.initialize(key, encodeSqrtPriceX96(1, 1))

        // 1) Add liquidity balances to AMM
        await modifyPositionTest.modifyPosition(key, {
          tickLower: getMinTick(10),
          tickUpper: getMaxTick(10),
          liquidityDelta: amountLiquidity,
        })
        await modifyPositionTest.modifyPosition(key, {
          tickLower: -20000,
          tickUpper: 20000,
          liquidityDelta: amountLiquidity,
        })

        liquidityBalance = await token0.balanceOf(poolManager.address)
      })

      it('balances clear properly w/ token1 excess', async () => {
        const amountSell0 = expandTo18Decimals(1)
        const amountSell1 = expandTo18Decimals(10)

        await ethers.provider.send('evm_setAutomine', [false])

        // 2) Add order balances to TWAMM
        await twamm.submitLongTermOrder(key, orderKey0, amountSell0)
        await twamm.submitLongTermOrder(key, orderKey1, amountSell1)

        await ethers.provider.send('evm_mine', [start])
        await ethers.provider.send('evm_setAutomine', [true])
        await ethers.provider.send('evm_setNextBlockTimestamp', [expiration + 1000])

        const prevBalance0 = await token0.balanceOf(twamm.address)
        const prevBalance1 = await token1.balanceOf(twamm.address)

        await twamm.executeTWAMMOrders(key)

        const newBalance0 = await token0.balanceOf(twamm.address)
        const newBalance1 = await token1.balanceOf(twamm.address)

        const earningsToken1 = await twamm.callStatic.claimEarningsOnLongTermOrder(key, orderKey0)
        const earningsToken0 = await twamm.callStatic.claimEarningsOnLongTermOrder(key, orderKey1)

        // TODO: precision error of 3-4 wei :(
        expect(newBalance0.sub(EXTRA_TOKENS)).to.eq(earningsToken0.sub(4))
        expect(newBalance1.sub(EXTRA_TOKENS)).to.eq(earningsToken1.sub(3))
      })

      it('balances clear properly w/ token0 excess', async () => {
        const amountSell0 = expandTo18Decimals(10)
        const amountSell1 = expandTo18Decimals(1)

        await ethers.provider.send('evm_setAutomine', [false])

        // 2) Add order balances to TWAMM
        await twamm.submitLongTermOrder(key, orderKey0, amountSell0)
        await twamm.submitLongTermOrder(key, orderKey1, amountSell1)

        await ethers.provider.send('evm_mine', [start])
        await ethers.provider.send('evm_setAutomine', [true])
        await ethers.provider.send('evm_setNextBlockTimestamp', [expiration + 1000])

        const prevBalance0 = await token0.balanceOf(twamm.address)
        const prevBalance1 = await token1.balanceOf(twamm.address)

        await twamm.executeTWAMMOrders(key)

        const newBalance0 = await token0.balanceOf(twamm.address)
        const newBalance1 = await token1.balanceOf(twamm.address)

        const earningsToken1 = await twamm.callStatic.claimEarningsOnLongTermOrder(key, orderKey0)
        const earningsToken0 = await twamm.callStatic.claimEarningsOnLongTermOrder(key, orderKey1)

        // TODO: precision error of 5-6 wei :(
        expect(newBalance0.sub(EXTRA_TOKENS)).to.eq(earningsToken0.sub(5))
        expect(newBalance1.sub(EXTRA_TOKENS)).to.eq(earningsToken1.sub(6))
      })
    })

    describe('when TWAMM crosses no ticks', () => {
      let latestTimestamp: number
      let amountLiquidity: BigNumber
      let amountSell0: BigNumber
      let amountSell1: BigNumber
      let start: number
      let expiration: number
      let orderKey0: OrderKey
      let orderKey1: OrderKey
      let key: PoolKey

      beforeEach(async () => {
        latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
        amountLiquidity = expandTo18Decimals(1)
        amountSell0 = expandTo18Decimals(1)
        amountSell1 = expandTo18Decimals(10)

        start = nIntervalsFrom(latestTimestamp, 10_000, 1)
        expiration = nIntervalsFrom(latestTimestamp, 10_000, 3)
        orderKey0 = {
          zeroForOne: true,
          owner: wallet.address,
          expiration,
        }
        orderKey1 = {
          zeroForOne: false,
          owner: wallet.address,
          expiration,
        }
        key = {
          token0: token0.address,
          token1: token1.address,
          fee: 0,
          hooks: twamm.address,
          tickSpacing: 10,
        }
      })

      it('clears all balances appropriately when trading against a 0 fee AMM', async () => {
        await poolManager.initialize(key, encodeSqrtPriceX96(1, 1))

        // 1) Add liquidity balances to AMM
        await modifyPositionTest.modifyPosition(key, {
          tickLower: getMinTick(10),
          tickUpper: getMaxTick(10),
          liquidityDelta: amountLiquidity,
        })

        // 2) Add order balances to TWAMM
        await inOneBlock(start, async () => {
          await twamm.submitLongTermOrder(key, orderKey0, amountSell0)
          await twamm.submitLongTermOrder(key, orderKey1, amountSell1)
        })

        await ethers.provider.send('evm_setNextBlockTimestamp', [expiration + 1000])

        const prevBalance0 = await token0.balanceOf(twamm.address)
        const prevBalance1 = await token1.balanceOf(twamm.address)

        await twamm.executeTWAMMOrders(key)

        const newBalance0 = await token0.balanceOf(twamm.address)
        const newBalance1 = await token1.balanceOf(twamm.address)

        const earningsToken1 = await twamm.callStatic.claimEarningsOnLongTermOrder(key, orderKey0)
        const earningsToken0 = await twamm.callStatic.claimEarningsOnLongTermOrder(key, orderKey1)

        // TODO: precision error of 3-4 wei :(
        expect(newBalance0.sub(EXTRA_TOKENS)).to.eq(earningsToken0.sub(3))
        expect(newBalance1.sub(EXTRA_TOKENS)).to.eq(earningsToken1.sub(4))
      })

      it('trades properly with initialized ticks just past the the target price moving right', async () => {
        await poolManager.initialize(key, encodeSqrtPriceX96(1, 1))

        // 1) Add liquidity balances to AMM
        await modifyPositionTest.modifyPosition(key, {
          tickLower: getMinTick(10),
          tickUpper: getMaxTick(10),
          liquidityDelta: amountLiquidity,
        })
        // Add initialized ticks closely past targetPrice
        await modifyPositionTest.modifyPosition(key, {
          tickLower: 23000,
          tickUpper: 23100,
          liquidityDelta: amountLiquidity,
        })

        // 2) Add order balances to TWAMM
        await inOneBlock(start, async () => {
          await twamm.submitLongTermOrder(key, orderKey0, amountSell0)
          await twamm.submitLongTermOrder(key, orderKey1, amountSell1)
        })

        await ethers.provider.send('evm_setNextBlockTimestamp', [expiration + 1000])
        await twamm.executeTWAMMOrders(key)
        // ensure we've swapped to the correct tick
        expect((await poolManager.getSlot0(key)).tick).to.eq(22989)
      })

      it('trades properly with initialized ticks just past the the target price moving left', async () => {
        await poolManager.initialize(key, encodeSqrtPriceX96(1, 1))

        // 1) Add liquidity balances to AMM
        await modifyPositionTest.modifyPosition(key, {
          tickLower: getMinTick(10),
          tickUpper: getMaxTick(10),
          liquidityDelta: amountLiquidity,
        })
        // Add initialized ticks closely past targetPrice
        await modifyPositionTest.modifyPosition(key, {
          tickLower: -23100,
          tickUpper: -23000,
          liquidityDelta: amountLiquidity,
        })

        // 2) Add order balances to TWAMM
        await inOneBlock(start, async () => {
          await twamm.submitLongTermOrder(key, orderKey0, amountSell1)
          await twamm.submitLongTermOrder(key, orderKey1, amountSell0)
        })

        await ethers.provider.send('evm_setNextBlockTimestamp', [expiration + 1000])
        await twamm.executeTWAMMOrders(key)
        // ensure we've swapped to the correct tick
        expect((await poolManager.getSlot0(key)).tick).to.eq(-22990)
      })
    })

    describe('single pool sell', () => {
      beforeEach('set up pool', async () => {
        const latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
        const amountLiquidity = expandTo18Decimals(1)

        start = nIntervalsFrom(latestTimestamp, 10_000, 1)
        expiration = nIntervalsFrom(latestTimestamp, 10_000, 3)

        orderKey0 = {
          zeroForOne: true,
          owner: wallet.address,
          expiration,
        }

        key = {
          token0: token0.address,
          token1: token1.address,
          fee: 0,
          hooks: twamm.address,
          tickSpacing: 10,
        }
        await poolManager.initialize(key, encodeSqrtPriceX96(1, 1))

        // 1) Add liquidity balances to AMM
        await modifyPositionTest.modifyPosition(key, {
          tickLower: getMinTick(10),
          tickUpper: getMaxTick(10),
          liquidityDelta: amountLiquidity,
        })
        await modifyPositionTest.modifyPosition(key, {
          tickLower: -2000,
          tickUpper: 2000,
          liquidityDelta: amountLiquidity,
        })
        await modifyPositionTest.modifyPosition(key, {
          tickLower: -3000,
          tickUpper: 3000,
          liquidityDelta: amountLiquidity,
        })
      })

      describe('when crossing two ticks', () => {
        it('receives the predicted earnings from the amm', async () => {
          await ethers.provider.send('evm_setNextBlockTimestamp', [start])

          await twamm.submitLongTermOrder(key, orderKey0, expandTo18Decimals(5))

          await ethers.provider.send('evm_setNextBlockTimestamp', [expiration + 300])
          await twamm.executeTWAMMOrders(key)

          const newBalance0 = await token0.balanceOf(twamm.address)
          const newBalance1 = await token1.balanceOf(twamm.address)

          const earningsToken1 = await twamm.callStatic.claimEarningsOnLongTermOrder(key, orderKey0)

          // TODO: precision error of 8/11 wei :(
          expect(newBalance0).to.equal(BigNumber.from(EXTRA_TOKENS).sub(8))
          expect(newBalance1.sub(EXTRA_TOKENS)).to.equal(earningsToken1.sub(11))
        })
      })
    })

    describe('twamm math resolves for extreme sell ratios', async () => {
      let poolKey: PoolKey
      let orderKey0: OrderKey
      let orderKey1: OrderKey
      let submitTimestamp: number
      let expirationTimestamp: number

      beforeEach(async () => {
        const latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
        const interval = 10_000
        submitTimestamp = nIntervalsFrom(latestTimestamp, interval, 1)
        expirationTimestamp = nIntervalsFrom(latestTimestamp, interval, 2)
        orderKey0 = {
          zeroForOne: true,
          owner: wallet.address,
          expiration: expirationTimestamp,
        }
        orderKey1 = {
          zeroForOne: false,
          owner: wallet.address,
          expiration: expirationTimestamp,
        }
        poolKey = {
          token0: token0.address,
          token1: token1.address,
          fee: 0,
          hooks: twamm.address,
          tickSpacing: 10,
        }

        await poolManager.initialize(poolKey, encodeSqrtPriceX96(1, 1))
        await modifyPositionTest.modifyPosition(poolKey, {
          tickLower: getMinTick(10),
          tickUpper: getMaxTick(10),
          liquidityDelta: expandTo18Decimals(1),
        })
      })

      it('swaps to high price (going right)', async () => {
        // increase liquidity so that we are testing not ending at the sqrtSellRatio
        await modifyPositionTest.modifyPosition(poolKey, {
          tickLower: getMinTick(10),
          tickUpper: getMaxTick(10),
          liquidityDelta: '1000000000000000000000000',
        })
        const balance0 = await token0.balanceOf(twamm.address)
        const balance1 = await token1.balanceOf(twamm.address)

        const amountSell0 = BigNumber.from('100000')
        const amountSell1 = BigNumber.from('34025678683638809405905696563977446090000000')
        await inOneBlock(submitTimestamp, async () => {
          await twamm.submitLongTermOrder(poolKey, orderKey0, amountSell0)
          await twamm.submitLongTermOrder(poolKey, orderKey1, amountSell1)
        })

        await ethers.provider.send('evm_setNextBlockTimestamp', [expirationTimestamp + 1000])
        await twamm.executeTWAMMOrders(poolKey)

        const newBalance0 = (await token0.balanceOf(twamm.address)).sub(balance0)
        const newBalance1 = (await token1.balanceOf(twamm.address)).sub(balance1)

        const earningsToken1 = await twamm.callStatic.claimEarningsOnLongTermOrder(poolKey, orderKey0)
        const earningsToken0 = await twamm.callStatic.claimEarningsOnLongTermOrder(poolKey, orderKey1)

        const expectedSqrtRatioX96 = '1390179360050332758641088620197702593046604939264'

        const finalPriceX96 = (await poolManager.getSlot0(poolKey)).sqrtPriceX96

        expect(finalPriceX96).to.equal(expectedSqrtRatioX96)

        const error0 = newBalance0.sub(earningsToken0)
        const error1 = newBalance1.sub(earningsToken1)

        // TODO: precision error :(
        // high errors bc extreme prices?
        expect(newBalance0.sub(error0)).to.eq(earningsToken0)
        expect(newBalance1.sub(error1)).to.eq(earningsToken1)
      })

      it('swaps to low price (going left)', async () => {
        // increase liquidity so that we are testing not ending at the sqrtSellRatio
        await modifyPositionTest.modifyPosition(poolKey, {
          tickLower: getMinTick(10),
          tickUpper: getMaxTick(10),
          liquidityDelta: '1000000000000000000000000',
        })
        const balance0 = await token0.balanceOf(twamm.address)
        const balance1 = await token1.balanceOf(twamm.address)

        console.log(balance0.toString())
        console.log(balance1.toString())

        const amountSell0 = BigNumber.from('34025678683638809405905696563977446090000000')
        const amountSell1 = BigNumber.from('100000')

        await inOneBlock(submitTimestamp, async () => {
          await twamm.submitLongTermOrder(poolKey, orderKey0, amountSell0)
          await twamm.submitLongTermOrder(poolKey, orderKey1, amountSell1)
        })

        await ethers.provider.send('evm_setNextBlockTimestamp', [expirationTimestamp + 1000])
        await twamm.executeTWAMMOrders(poolKey)

        const newBalance0 = (await token0.balanceOf(twamm.address)).sub(balance0)
        const newBalance1 = (await token1.balanceOf(twamm.address)).sub(balance1)

        const earningsToken1 = await twamm.callStatic.claimEarningsOnLongTermOrder(poolKey, orderKey0)
        const earningsToken0 = await twamm.callStatic.claimEarningsOnLongTermOrder(poolKey, orderKey1)

        const expectedSqrtRatioX96 = '4515317890'

        const finalPriceX96 = (await poolManager.getSlot0(poolKey)).sqrtPriceX96

        expect(finalPriceX96).to.equal(expectedSqrtRatioX96)

        const error0 = newBalance0.sub(earningsToken0)
        const error1 = newBalance1.sub(earningsToken1)

        // TODO: precision error :(
        // high errors bc extreme prices?
        expect(newBalance0.sub(error0)).to.eq(earningsToken0)
        expect(newBalance1.sub(error1)).to.eq(earningsToken1)
      })

      it('swaps going right to sqrtSellRatio and does not revert when target tick is an initialized tick', async () => {
        const balance0 = await token0.balanceOf(twamm.address)
        const balance1 = await token1.balanceOf(twamm.address)

        const amountSell0 = BigNumber.from('100000')
        const amountSell1 = BigNumber.from('33112798684424369649027597812633277504400000')

        await inOneBlock(submitTimestamp, async () => {
          await twamm.submitLongTermOrder(poolKey, orderKey0, amountSell0)
          await twamm.submitLongTermOrder(poolKey, orderKey1, amountSell1)
        })

        const tickAtSqrtSellRatio = 887000

        await modifyPositionTest.modifyPosition(poolKey, {
          tickLower: tickAtSqrtSellRatio,
          tickUpper: tickAtSqrtSellRatio + 200,
          liquidityDelta: expandTo18Decimals(1),
        })

        await ethers.provider.send('evm_setNextBlockTimestamp', [expirationTimestamp + 1000])
        await twamm.executeTWAMMOrders(poolKey)

        const newBalance0 = (await token0.balanceOf(twamm.address)).sub(balance0)
        const newBalance1 = (await token1.balanceOf(twamm.address)).sub(balance1)

        const earningsToken1 = await twamm.callStatic.claimEarningsOnLongTermOrder(poolKey, orderKey0)
        const earningsToken0 = await twamm.callStatic.claimEarningsOnLongTermOrder(poolKey, orderKey1)

        const expectedPriceX96 = '1441708729548066551791643897157159050890912464896'

        // TODO check desmos
        const poolPrice = (await poolManager.getSlot0(poolKey)).sqrtPriceX96

        expect(poolPrice).to.equal(expectedPriceX96)

        const error0 = newBalance0.sub(earningsToken0)
        const error1 = newBalance1.sub(earningsToken1)

        // TODO: precision error ?
        expect(newBalance0.sub(error0)).to.eq(earningsToken0)
        expect(newBalance1.sub(error1)).to.eq(earningsToken1)
      })

      it('swaps to to sqrtSellRatio going left and does not error when target tick is initialized tick', async () => {
        const balance0 = await token0.balanceOf(twamm.address)
        const balance1 = await token1.balanceOf(twamm.address)
        const amountSell0 = '34015678683638809405905696563977446090000000'
        const amountSell1 = '100000'

        await inOneBlock(submitTimestamp, async () => {
          await twamm.submitLongTermOrder(poolKey, orderKey0, amountSell0)
          await twamm.submitLongTermOrder(poolKey, orderKey1, amountSell1)
        })

        await ethers.provider.send('evm_setNextBlockTimestamp', [expirationTimestamp + 1000])

        await twamm.executeTWAMMOrders(poolKey)

        const newBalance0 = (await token0.balanceOf(twamm.address)).sub(balance0)
        const newBalance1 = (await token1.balanceOf(twamm.address)).sub(balance1)

        const earningsToken1 = await twamm.callStatic.claimEarningsOnLongTermOrder(poolKey, orderKey0)
        const earningsToken0 = await twamm.callStatic.claimEarningsOnLongTermOrder(poolKey, orderKey1)

        // sqrtSellRatio
        const expectedPriceX96 = 4295760037

        expect((await poolManager.getSlot0(poolKey)).sqrtPriceX96).to.equal(expectedPriceX96)

        const error0 = newBalance0.sub(earningsToken0)
        const error1 = newBalance1.sub(earningsToken1)

        // TODO: precision error?
        // why so high
        expect(newBalance0.sub(error0)).to.eq(earningsToken0)
        expect(newBalance1.sub(error1)).to.eq(earningsToken1)
      })
    })

    describe('when AMM liquidity is extremely low causing severe price impact', async () => {
      let poolKey: PoolKey
      let orderKey0: OrderKey
      let orderKey1: OrderKey
      let submitTimestamp: number
      let expirationTimestamp: number

      beforeEach(async () => {
        const latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
        submitTimestamp = nIntervalsFrom(latestTimestamp, 10_000, 1)
        expirationTimestamp = nIntervalsFrom(latestTimestamp, 10_000, 3)
        orderKey0 = {
          zeroForOne: true,
          owner: wallet.address,
          expiration: expirationTimestamp,
        }
        orderKey1 = {
          zeroForOne: false,
          owner: wallet.address,
          expiration: expirationTimestamp,
        }
        poolKey = {
          token0: token0.address,
          token1: token1.address,
          fee: 0,
          hooks: twamm.address,
          tickSpacing: 10,
        }

        await poolManager.initialize(poolKey, encodeSqrtPriceX96(1, 1))
        await modifyPositionTest.modifyPosition(poolKey, {
          tickLower: getMinTick(10),
          tickUpper: getMaxTick(10),
          liquidityDelta: '100',
        })
      })

      describe('with token1 excess', async () => {
        it('it sets the pool price to the TWAMM sell ratio and twamm hook has token balances equal to earnings', async () => {
          const amountSell0 = expandTo18Decimals(1)
          const amountSell1 = expandTo18Decimals(10)

          await inOneBlock(submitTimestamp, async () => {
            await twamm.submitLongTermOrder(poolKey, orderKey0, amountSell0)
            await twamm.submitLongTermOrder(poolKey, orderKey1, amountSell1)
          })

          await ethers.provider.send('evm_setNextBlockTimestamp', [expirationTimestamp + 1000])
          await twamm.executeTWAMMOrders(poolKey)

          const newBalance0 = await token0.balanceOf(twamm.address)
          const newBalance1 = await token1.balanceOf(twamm.address)

          const earningsToken1 = await twamm.callStatic.claimEarningsOnLongTermOrder(poolKey, orderKey0)
          const earningsToken0 = await twamm.callStatic.claimEarningsOnLongTermOrder(poolKey, orderKey1)

          const sqrtX96SellRate = encodeSqrtPriceX96(amountSell1, amountSell0)
          expect((await poolManager.getSlot0(poolKey)).sqrtPriceX96).to.equal(sqrtX96SellRate)

          // TODO: precision error of 8 wei :(
          expect(newBalance0.sub(EXTRA_TOKENS)).to.eq(earningsToken0.sub(4))
          expect(newBalance1.sub(EXTRA_TOKENS)).to.eq(earningsToken1.sub(3))
        })
      })

      describe('with token0 excess', async () => {
        it('it sets the pool price to the TWAMM sell ratio and twamm hook has token balances equal to earnings', async () => {
          const amountSell0 = expandTo18Decimals(100)
          const amountSell1 = expandTo18Decimals(1)

          await inOneBlock(submitTimestamp, async () => {
            await twamm.submitLongTermOrder(poolKey, orderKey0, amountSell0)
            await twamm.submitLongTermOrder(poolKey, orderKey1, amountSell1)
          })

          await ethers.provider.send('evm_setNextBlockTimestamp', [expirationTimestamp + 1000])
          await twamm.executeTWAMMOrders(poolKey)

          const newBalance0 = await token0.balanceOf(twamm.address)
          const newBalance1 = await token1.balanceOf(twamm.address)

          const earningsToken1 = await twamm.callStatic.claimEarningsOnLongTermOrder(poolKey, orderKey0)
          const earningsToken0 = await twamm.callStatic.claimEarningsOnLongTermOrder(poolKey, orderKey1)

          const sqrtX96SellRate = encodeSqrtPriceX96(amountSell1, amountSell0)
          expect((await poolManager.getSlot0(poolKey)).sqrtPriceX96).to.equal(sqrtX96SellRate)

          // TODO: precision error of 7-9 wei :(
          expect(newBalance0.sub(EXTRA_TOKENS)).to.eq(earningsToken0.sub(9))
          expect(newBalance1.sub(EXTRA_TOKENS)).to.eq(earningsToken1.sub(7))
        })
      })

      describe('with only token0 selling in TWAMM', async () => {
        it('it sets the pool price to the TWAMM sell ratio and twamm hook has token balances equal to earnings', async () => {
          const amountSell0 = expandTo18Decimals(1)

          await inOneBlock(submitTimestamp, async () => {
            await twamm.submitLongTermOrder(poolKey, orderKey0, amountSell0)
          })

          await ethers.provider.send('evm_setNextBlockTimestamp', [expirationTimestamp + 1000])
          await twamm.executeTWAMMOrders(poolKey)

          const newBalance1 = await token1.balanceOf(twamm.address)
          const earningsToken1 = await twamm.callStatic.claimEarningsOnLongTermOrder(poolKey, orderKey0)

          // TODO: precision error of 15 wei :(
          expect(newBalance1.sub(EXTRA_TOKENS)).to.eq(earningsToken1.sub(15))
        })
      })
    })
  })
})
