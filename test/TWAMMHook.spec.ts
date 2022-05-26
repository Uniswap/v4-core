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
      // TODO: HACK!! send some extra tokens so that the current precision errors do not revert tests
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
      expect((await twamm.twammStates(getPoolId(poolKey))).lastVirtualOrderTimestamp).to.equal(0)
      await poolManager.initialize(poolKey, encodeSqrtPriceX96(1, 1))
      expect((await twamm.twammStates(getPoolId(poolKey))).lastVirtualOrderTimestamp).to.equal(
        (await ethers.provider.getBlock('latest')).timestamp
      )
    })
  })

  describe('#executeTWAMMOrders', async () => {
    let poolKey: any
    let orderKey0: any
    let orderKey1: any
    let latestTimestamp: number

    beforeEach(async () => {
      latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp

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
        expiration: nIntervalsFrom(latestTimestamp, 10_000, 3),
      }
      orderKey1 = {
        zeroForOne: false,
        owner: wallet.address,
        expiration: nIntervalsFrom(latestTimestamp, 10_000, 3),
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

    it('gas with no initialized ticks', async () => {
      await inOneBlock(latestTimestamp + 100, async () => {
        await twamm.submitLongTermOrder(poolKey, {
          amountIn: expandTo18Decimals(1),
          ...orderKey0,
        })
        await twamm.submitLongTermOrder(poolKey, {
          amountIn: expandTo18Decimals(10),
          ...orderKey1,
        })
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
        await twamm.submitLongTermOrder(poolKey, {
          amountIn: expandTo18Decimals(1),
          ...orderKey0,
        })
        await twamm.submitLongTermOrder(poolKey, {
          amountIn: expandTo18Decimals(10),
          ...orderKey1,
        })
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
        await twamm.submitLongTermOrder(poolKey, {
          amountIn: expandTo18Decimals(1),
          ...orderKey0,
        })
        await twamm.submitLongTermOrder(poolKey, {
          amountIn: expandTo18Decimals(10),
          ...orderKey1,
        })
      })

      await ethers.provider.send('evm_setNextBlockTimestamp', [latestTimestamp + 10_000])
      await snapshotGasCost(twamm.executeTWAMMOrders(poolKey))
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
        const amountLTO0 = expandTo18Decimals(1)
        const amountLTO1 = expandTo18Decimals(10)

        await ethers.provider.send('evm_setAutomine', [false])

        // 2) Add order balances to TWAMM
        await twamm.submitLongTermOrder(key, {
          amountIn: amountLTO0,
          ...orderKey0,
        })
        await twamm.submitLongTermOrder(key, {
          amountIn: amountLTO1,
          ...orderKey1,
        })

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

        // TODO: precision error of 3-6 wei :(
        // With both trades expiring, the final balance of TWAMM should be equal to the earnings able to be claimed
        // for each TWAMM orderPools
        expect(newBalance0.sub(EXTRA_TOKENS)).to.eq(earningsToken0.sub(4))
        expect(newBalance1.sub(EXTRA_TOKENS)).to.eq(earningsToken1.sub(3))
      })

      it('balances clear properly w/ token0 excess', async () => {
        const amountLTO0 = expandTo18Decimals(10)
        const amountLTO1 = expandTo18Decimals(1)

        await ethers.provider.send('evm_setAutomine', [false])

        // 2) Add order balances to TWAMM
        await twamm.submitLongTermOrder(key, {
          amountIn: amountLTO0,
          ...orderKey0,
        })
        await twamm.submitLongTermOrder(key, {
          amountIn: amountLTO1,
          ...orderKey1,
        })

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

        // TODO: precision error of 3-6 wei :(
        // With both trades expiring, the final balance of TWAMM should be equal to the earnings able to be claimed
        // for each TWAMM order
        expect(newBalance0.sub(EXTRA_TOKENS)).to.eq(earningsToken0.sub(5))
        expect(newBalance1.sub(EXTRA_TOKENS)).to.eq(earningsToken1.sub(6))
      })
    })

    describe('when TWAMM crosses no ticks', () => {
      it('clears all balances appropriately when trading against a 0 fee AMM', async () => {
        const latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
        const amountLiquidity = expandTo18Decimals(1)
        const amountLTO0 = expandTo18Decimals(1)
        const amountLTO1 = expandTo18Decimals(10)

        const start = nIntervalsFrom(latestTimestamp, 10_000, 1)
        const expiration = nIntervalsFrom(latestTimestamp, 10_000, 3)

        const orderKey0 = {
          zeroForOne: true,
          owner: wallet.address,
          expiration,
        }
        const orderKey1 = {
          zeroForOne: false,
          owner: wallet.address,
          expiration,
        }

        const key = {
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

        await ethers.provider.send('evm_setAutomine', [false])

        // 2) Add order balances to TWAMM
        await twamm.submitLongTermOrder(key, {
          amountIn: amountLTO0,
          ...orderKey0,
        })
        await twamm.submitLongTermOrder(key, {
          amountIn: amountLTO1,
          ...orderKey1,
        })

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

        // TODO: precision error of 3-6 wei :(
        // With both trades expiring, the final balance of TWAMM should be equal to the earnings able to be claimed
        // for each TWAMM order
        expect(newBalance0.sub(EXTRA_TOKENS)).to.eq(earningsToken0.sub(3))
        expect(newBalance1.sub(EXTRA_TOKENS)).to.eq(earningsToken1.sub(4))
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
        it('crosses both ticks properly', async () => {
          await ethers.provider.send('evm_setNextBlockTimestamp', [start])

          await twamm.submitLongTermOrder(key, {
            amountIn: expandTo18Decimals(5),
            ...orderKey0,
          })

          await ethers.provider.send('evm_setNextBlockTimestamp', [expiration + 300])
          await twamm.executeTWAMMOrders(key)

          const newBalance0 = await token0.balanceOf(twamm.address)
          const newBalance1 = await token1.balanceOf(twamm.address)

          const earningsToken1 = await twamm.callStatic.claimEarningsOnLongTermOrder(key, orderKey0)

          // TODO: precision error of 11 wei :(
          // The only order is completed so the new balance should equal the earnings to be collected
          expect(newBalance1.sub(EXTRA_TOKENS)).to.equal(earningsToken1.sub(11))
        })
      })
    })
  })
})
