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
import { inOneBlock, mineNextBlock, setNextBlocktime } from './shared/evmHelpers'

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

// setting an intial token balance is helpful in evaluating exact earnings. Precision errors could cause earnings owed
// to be larger than twamm balance, in which case twamm balance will just go to 0. This could obscure larger,
// unacceptable precision errors.
const INITIAL_TOKEN_BALANCE = 20
const CONTROLLER_GAS_LIMIT = 50_000
const EXPIRATION_INTERVAL = 10_000

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
    const manager = (await poolManagerFactory.deploy(CONTROLLER_GAS_LIMIT)) as PoolManager

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
      await getDeployedTWAMMCode(manager.address, EXPIRATION_INTERVAL),
    ])

    const twamm: TWAMMHook = twammFactory.attach(twammHookAddress) as TWAMMHook

    const swapTest = (await swapTestFactory.deploy(manager.address)) as PoolSwapTest
    const modifyPositionTest = (await modifyPositionTestFactory.deploy(manager.address)) as PoolModifyPositionTest

    for (const token of [tokens.token0, tokens.token1]) {
      // seed twamm with starting balances so we can test exact numbers even when precision errors cause us to transfer
      // only the token balance when the earningsAmount was greater than the balance by a small wei amount
      token.transfer(twamm.address, INITIAL_TOKEN_BALANCE)
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
    const { sqrtPriceX96 } = await poolManager.getSlot0(getPoolId(poolKey))
    expect(sqrtPriceX96, 'pool is not initialized').to.eq(0)
    // it seems like the waffle fixture is not working correctly (perhaps due to hardhat_setCode), and if we don't
    // do this and revert in afterEach, the pool is already initialized
    snapshotId = await hre.network.provider.send('evm_snapshot')
  })

  afterEach('revert', async () => {
    // see the beforeEach hook
    await hre.network.provider.send('evm_revert', [snapshotId])
  })

  it('bytecode size', async () => {
    expect(((await ethers.provider.getCode(twamm.address)).length - 2) / 2).to.matchSnapshot()
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

  describe('#submitLongTermOrder', () => {
    let latestTimestamp: number
    let poolKey: PoolKey

    beforeEach('setup amm pool', async () => {
      poolKey = {
        token0: token0.address,
        token1: token1.address,
        fee: 0,
        hooks: twamm.address,
        tickSpacing: 10,
      }
      latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
      await setNextBlocktime(nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 1))
      await poolManager.initialize(poolKey, encodeSqrtPriceX96(1, 1))

      await modifyPositionTest.modifyPosition(poolKey, {
        tickLower: getMinTick(10),
        tickUpper: getMaxTick(10),
        liquidityDelta: expandTo18Decimals(1),
      })
    })

    it('stores the long term order under the correct pool', async () => {
      const expiration = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 3)
      const orderKey = {
        zeroForOne: true,
        owner: wallet.address,
        expiration,
      }

      const nullOrder = await twamm.getOrder(poolKey, orderKey)

      await twamm.submitLongTermOrder(poolKey, orderKey, expandTo18Decimals(10))
      const order = await twamm.getOrder(poolKey, orderKey)
      expect(order.earningsFactorLast).to.eq(0)
    })

    it('stores the correct earningsFactorLast if past earnings have been processed', async () => {
      const expiration = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 2)
      const orderKey0 = {
        zeroForOne: true,
        owner: wallet.address,
        expiration,
      }
      const orderKey1 = {
        zeroForOne: true,
        owner: wallet.address,
        expiration: nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 5),
      }
      await twamm.submitLongTermOrder(poolKey, orderKey0, expandTo18Decimals(10))
      await setNextBlocktime(expiration + 100)
      await twamm.submitLongTermOrder(poolKey, orderKey1, expandTo18Decimals(10))
      const order = await twamm.getOrder(poolKey, orderKey1)

      expect(order.earningsFactorLast).to.eq((await twamm.getOrderPool(poolKey, true)).earningsFactorCurrent)
    })

    it('emits a SubmitLongTermOrder event', async () => {
      const expiration = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 3)
      const orderAmount = expandTo18Decimals(10)
      const orderKey = {
        zeroForOne: true,
        owner: wallet.address,
        expiration,
      }

      await setNextBlocktime(expiration - EXPIRATION_INTERVAL)
      await expect(twamm.submitLongTermOrder(poolKey, orderKey, orderAmount))
        .to.emit(twamm, 'SubmitLongTermOrder')
        .withArgs(getPoolId(poolKey), wallet.address, expiration, true, orderAmount.div(EXPIRATION_INTERVAL), 0)
    })

    it('gas', async () => {
      const expiration = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 3)
      const orderKey0 = {
        zeroForOne: true,
        owner: wallet.address,
        expiration,
      }

      // difficult to isolate gas from #executeTWAMMOrders()
      await snapshotGasCost(twamm.submitLongTermOrder(poolKey, orderKey0, expandTo18Decimals(10)))
    })
  })

  describe('#updateLongTermOrder', () => {
    let orderKey0: OrderKey
    let orderKey1: OrderKey
    let poolKey: PoolKey
    let latestTimestamp: number
    let expiration: number
    let halfwayTimestamp: number
    let orderAmount: BigNumber

    beforeEach('setup pool and twamm', async () => {
      latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
      expiration = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 6)
      halfwayTimestamp = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 4)
      orderAmount = expandTo18Decimals(10)

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

      await setNextBlocktime(nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 1))
      await poolManager.initialize(poolKey, encodeSqrtPriceX96(1, 1))

      await modifyPositionTest.modifyPosition(poolKey, {
        tickLower: getMinTick(10),
        tickUpper: getMaxTick(10),
        liquidityDelta: expandTo18Decimals(1),
      })

      await inOneBlock(nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 2), async () => {
        await twamm.submitLongTermOrder(poolKey, orderKey0, orderAmount)
        await twamm.submitLongTermOrder(poolKey, orderKey1, orderAmount)
      })
    })

    describe('for orders trading zeroForOne', () => {
      it('claims rewards, decreases sellRate, and updates sellTokensOwed to owner', async () => {
        const amountDelta = orderAmount.div(10)
        await setNextBlocktime(halfwayTimestamp)
        await twamm.updateLongTermOrder(poolKey, orderKey0, amountDelta.mul(-1))
        const order = await twamm.getOrder(poolKey, orderKey0)
        const { earningsFactorCurrent } = await twamm.getOrderPool(poolKey, true)

        expect(order.sellRate).to.eq(200000000000000)
        expect(order.earningsFactorLast).to.eq(earningsFactorCurrent)
        expect(await twamm.tokensOwed(poolKey.token0, orderKey0.owner)).to.eq(amountDelta)
        expect(await twamm.tokensOwed(poolKey.token1, orderKey0.owner)).to.eq(orderAmount.div(2))
      })

      it('deletes order and returns all tokens if delta sent is -1', async () => {
        await setNextBlocktime(halfwayTimestamp)
        await twamm.updateLongTermOrder(poolKey, orderKey0, -1)
        const order = await twamm.getOrder(poolKey, orderKey0)
        const { earningsFactorCurrent } = await twamm.getOrderPool(poolKey, true)

        expect(order.sellRate).to.eq(0)
        expect(order.earningsFactorLast).to.eq(0)
        expect(await twamm.tokensOwed(poolKey.token0, orderKey0.owner)).to.eq(orderAmount.div(2))
        expect(await twamm.tokensOwed(poolKey.token1, orderKey0.owner)).to.eq(orderAmount.div(2))
      })

      it('claims rewards, increases sellRate, collects token0 balance if delta is positive', async () => {
        await setNextBlocktime(halfwayTimestamp)
        await twamm.updateLongTermOrder(poolKey, orderKey0, orderAmount)
        const order = await twamm.getOrder(poolKey, orderKey0)
        const { earningsFactorCurrent } = await twamm.getOrderPool(poolKey, true)

        expect(order.sellRate).to.eq(orderAmount.div(40_000).add(orderAmount.div(20_000)))
        expect(order.earningsFactorLast).to.eq(earningsFactorCurrent)
        expect(await twamm.tokensOwed(poolKey.token0, orderKey0.owner)).to.eq(0)
        expect(await twamm.tokensOwed(poolKey.token1, orderKey0.owner)).to.eq(orderAmount.div(2))
      })

      it('emits an UpdateLongTermOrder event', async () => {
        await setNextBlocktime(halfwayTimestamp)
        const updatedSellRate = orderAmount.div(40_000).add(orderAmount.div(20_000))
        const latestEarningsFactor = '0x4e20000000000000000000000000'
        await expect(twamm.updateLongTermOrder(poolKey, orderKey0, orderAmount))
          .to.emit(twamm, 'UpdateLongTermOrder')
          .withArgs(getPoolId(poolKey), wallet.address, expiration, true, updatedSellRate, latestEarningsFactor)
      })
    })

    describe('for orders trading oneForZero', () => {
      it('claims rewards, decreases sellRate, and transfers sell tokens if the delta is negative', async () => {
        const amountDelta = orderAmount.div(10)
        await setNextBlocktime(halfwayTimestamp)
        await twamm.updateLongTermOrder(poolKey, orderKey1, amountDelta.mul(-1))
        const order = await twamm.getOrder(poolKey, orderKey1)
        const { earningsFactorCurrent } = await twamm.getOrderPool(poolKey, false)

        expect(order.earningsFactorLast).to.eq(earningsFactorCurrent)
        expect(order.sellRate).to.eq(200000000000000)
        expect(await twamm.tokensOwed(poolKey.token0, orderKey0.owner)).to.eq(orderAmount.div(2))
        expect(await twamm.tokensOwed(poolKey.token1, orderKey0.owner)).to.eq(amountDelta)
      })

      it('deletes and returns all tokens if delta sent is -1', async () => {
        await setNextBlocktime(halfwayTimestamp)
        await twamm.updateLongTermOrder(poolKey, orderKey1, -1)
        const order = await twamm.getOrder(poolKey, orderKey1)

        expect(order.earningsFactorLast).to.eq(0)
        expect(order.sellRate).to.eq(0)
        expect(await twamm.tokensOwed(poolKey.token0, orderKey0.owner)).to.eq(orderAmount.div(2))
        expect(await twamm.tokensOwed(poolKey.token1, orderKey0.owner)).to.eq(orderAmount.div(2))
      })

      it('collects token1 balance if delta is positive and increases sellRate', async () => {
        await setNextBlocktime(halfwayTimestamp)
        await twamm.updateLongTermOrder(poolKey, orderKey1, orderAmount)
        const order = await twamm.getOrder(poolKey, orderKey1)
        const { earningsFactorCurrent } = await twamm.getOrderPool(poolKey, false)

        expect(order.earningsFactorLast).to.eq(earningsFactorCurrent)
        expect(order.sellRate).to.eq(orderAmount.div(40_000).add(orderAmount.div(20_000)))
        expect(await twamm.tokensOwed(poolKey.token0, orderKey0.owner)).to.eq(orderAmount.div(2))
        expect(await twamm.tokensOwed(poolKey.token1, orderKey0.owner)).to.eq(0)
      })

      it('emits an UpdateLongTermOrder event', async () => {
        await setNextBlocktime(halfwayTimestamp)
        const updatedSellRate = orderAmount.div(40_000).add(orderAmount.div(20_000))
        const latestEarningsFactor = '0x4e20000000000000000000000000'
        await expect(twamm.updateLongTermOrder(poolKey, orderKey1, orderAmount))
          .to.emit(twamm, 'UpdateLongTermOrder')
          .withArgs(getPoolId(poolKey), wallet.address, expiration, false, updatedSellRate, latestEarningsFactor)
      })
    })

    it('gas', async () => {
      await setNextBlocktime(expiration - 5_000)
      await snapshotGasCost(twamm.updateLongTermOrder(poolKey, orderKey0, expandTo18Decimals(10)))
    })
  })

  describe('#claimTokens', () => {
    let orderKey0: OrderKey
    let orderKey1: OrderKey
    let poolKey: PoolKey
    let latestTimestamp: number
    let expiration: number
    let orderAmount: BigNumber

    beforeEach('setup pool and twamm', async () => {
      latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
      orderAmount = expandTo18Decimals(10)
      expiration = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 6)

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

      await setNextBlocktime(nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 1))
      await poolManager.initialize(poolKey, encodeSqrtPriceX96(1, 1))

      await modifyPositionTest.modifyPosition(poolKey, {
        tickLower: getMinTick(10),
        tickUpper: getMaxTick(10),
        liquidityDelta: expandTo18Decimals(1),
      })

      await inOneBlock(nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 2), async () => {
        await twamm.submitLongTermOrder(poolKey, orderKey0, orderAmount)
        await twamm.submitLongTermOrder(poolKey, orderKey1, orderAmount)
      })
    })

    it('does not claim any tokens if 0 tokens are owed', async () => {
      const balanceBefore = await token0.balanceOf(wallet.address)
      await twamm.claimTokens(poolKey.token0, wallet.address, expandTo18Decimals(1))
      const balanceAfter = await token1.balanceOf(wallet.address)
      expect(balanceBefore).to.eq(balanceAfter)
    })

    it('claims full amount if amountRequested is 0', async () => {
      await setNextBlocktime(expiration - 3_000)
      await twamm.updateLongTermOrder(poolKey, orderKey0, 0)
      await twamm.updateLongTermOrder(poolKey, orderKey1, 0)

      const balance0Prev = await token0.balanceOf(wallet.address)
      const balance1Prev = await token1.balanceOf(wallet.address)

      const tokens0Owed = await twamm.tokensOwed(poolKey.token0, wallet.address)
      const tokens1Owed = await twamm.tokensOwed(poolKey.token1, wallet.address)

      await twamm.claimTokens(poolKey.token0, wallet.address, 0)
      await twamm.claimTokens(poolKey.token1, wallet.address, 0)

      const balance0New = await token0.balanceOf(wallet.address)
      const balance1New = await token1.balanceOf(wallet.address)

      expect(balance0New.sub(balance0Prev)).to.eq(tokens0Owed)
      expect(balance1New.sub(balance1Prev)).to.eq(tokens1Owed)
    })

    it('gas', async () => {
      await setNextBlocktime(expiration - 3_000)
      await twamm.updateLongTermOrder(poolKey, orderKey0, 0)
      // difficult to isolate gas from #executeTWAMMOrders()
      await snapshotGasCost(twamm.claimTokens(token0.address, wallet.address, expandTo18Decimals(1)))
    })
  })

  describe('#executeTWAMMOrders', () => {
    let poolKey: PoolKey
    let orderKey0: OrderKey
    let orderKey1: OrderKey
    let latestTimestamp: number
    let expiration: number

    beforeEach(async () => {
      latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
      expiration = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 3)

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

      await setNextBlocktime(nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 1))
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
        await setNextBlocktime(latestTimestamp + EXPIRATION_INTERVAL)
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
        await setNextBlocktime(latestTimestamp + EXPIRATION_INTERVAL)
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

        await setNextBlocktime(latestTimestamp + EXPIRATION_INTERVAL)
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
        await setNextBlocktime(latestTimestamp + 100)
        await twamm.submitLongTermOrder(poolKey, orderKey0, expandTo18Decimals(7))

        await setNextBlocktime(expiration + 300)
        await snapshotGasCost(twamm.executeTWAMMOrders(poolKey))
      })

      it('gas crossing 1 initialized tick', async () => {
        await modifyPositionTest.modifyPosition(poolKey, {
          tickLower: -2000,
          tickUpper: 2000,
          liquidityDelta: expandTo18Decimals(1),
        })

        await setNextBlocktime(latestTimestamp + 100)
        await twamm.submitLongTermOrder(poolKey, orderKey0, expandTo18Decimals(7))

        await setNextBlocktime(expiration + 300)
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

        await setNextBlocktime(latestTimestamp + 100)
        await twamm.submitLongTermOrder(poolKey, orderKey0, expandTo18Decimals(7))

        await setNextBlocktime(expiration + 300)
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

        start = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 1)
        expiration = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 3)

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
        await setNextBlocktime(expiration + 1000)

        const prevBalance0 = await token0.balanceOf(twamm.address)
        const prevBalance1 = await token1.balanceOf(twamm.address)

        await twamm.executeTWAMMOrders(key)
        await twamm.updateLongTermOrder(key, orderKey0, 0)
        await twamm.updateLongTermOrder(key, orderKey1, 0)

        const newBalance0 = await token0.balanceOf(twamm.address)
        const newBalance1 = await token1.balanceOf(twamm.address)

        const earningsToken0 = await twamm.tokensOwed(poolKey.token0, wallet.address)
        const earningsToken1 = await twamm.tokensOwed(poolKey.token1, wallet.address)

        // precision error of 3-4 wei
        expect(newBalance0.sub(INITIAL_TOKEN_BALANCE)).to.eq(earningsToken0.sub(4))
        expect(newBalance1.sub(INITIAL_TOKEN_BALANCE)).to.eq(earningsToken1.sub(3))
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
        await setNextBlocktime(expiration + 1000)

        const prevBalance0 = await token0.balanceOf(twamm.address)
        const prevBalance1 = await token1.balanceOf(twamm.address)

        await twamm.executeTWAMMOrders(key)
        await twamm.updateLongTermOrder(key, orderKey0, 0)
        await twamm.updateLongTermOrder(key, orderKey1, 0)

        const newBalance0 = await token0.balanceOf(twamm.address)
        const newBalance1 = await token1.balanceOf(twamm.address)

        const earningsToken0 = await twamm.tokensOwed(poolKey.token0, wallet.address)
        const earningsToken1 = await twamm.tokensOwed(poolKey.token1, wallet.address)

        // precision error of 5-6 wei
        expect(newBalance0.sub(INITIAL_TOKEN_BALANCE)).to.eq(earningsToken0.sub(5))
        expect(newBalance1.sub(INITIAL_TOKEN_BALANCE)).to.eq(earningsToken1.sub(6))
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

        start = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 1)
        expiration = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 3)
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

        await setNextBlocktime(expiration + 1000)

        const prevBalance0 = await token0.balanceOf(twamm.address)
        const prevBalance1 = await token1.balanceOf(twamm.address)

        await twamm.executeTWAMMOrders(key)
        await twamm.updateLongTermOrder(key, orderKey0, 0)
        await twamm.updateLongTermOrder(key, orderKey1, 0)

        const newBalance0 = await token0.balanceOf(twamm.address)
        const newBalance1 = await token1.balanceOf(twamm.address)

        const earningsToken0 = await twamm.tokensOwed(poolKey.token0, wallet.address)
        const earningsToken1 = await twamm.tokensOwed(poolKey.token1, wallet.address)

        // precision error of 3-4 wei
        expect(newBalance0.sub(INITIAL_TOKEN_BALANCE)).to.eq(earningsToken0.sub(3))
        expect(newBalance1.sub(INITIAL_TOKEN_BALANCE)).to.eq(earningsToken1.sub(4))
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

        await setNextBlocktime(expiration + 1000)
        await twamm.executeTWAMMOrders(key)
        // ensure we've swapped to the correct tick
        expect((await poolManager.getSlot0(getPoolId(key))).tick).to.eq(22989)
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

        await setNextBlocktime(expiration + 1000)
        await twamm.executeTWAMMOrders(key)
        // ensure we've swapped to the correct tick
        expect((await poolManager.getSlot0(getPoolId(key))).tick).to.eq(-22990)
      })
    })

    describe('single pool sell', () => {
      beforeEach('set up pool', async () => {
        const latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
        const amountLiquidity = expandTo18Decimals(1)

        start = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 1)
        expiration = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 3)

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
          await setNextBlocktime(start)

          await twamm.submitLongTermOrder(key, orderKey0, expandTo18Decimals(5))

          await setNextBlocktime(expiration + 300)
          await twamm.executeTWAMMOrders(key)
          await twamm.updateLongTermOrder(key, orderKey0, 0)

          const newBalance0 = await token0.balanceOf(twamm.address)
          const newBalance1 = await token1.balanceOf(twamm.address)

          const earningsToken1 = await twamm.tokensOwed(poolKey.token1, wallet.address)

          // precision error of 8/11 wei
          expect(newBalance0).to.equal(BigNumber.from(INITIAL_TOKEN_BALANCE).sub(8))
          expect(newBalance1.sub(INITIAL_TOKEN_BALANCE)).to.equal(earningsToken1.sub(11))
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
        const interval = EXPIRATION_INTERVAL
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

        const amountSell0 = BigNumber.from('100000')
        const amountSell1 = BigNumber.from('34025678683638809405905696563977446090000000')
        await inOneBlock(submitTimestamp, async () => {
          await twamm.submitLongTermOrder(poolKey, orderKey0, amountSell0)
          await twamm.submitLongTermOrder(poolKey, orderKey1, amountSell1)
        })

        await ethers.provider.send('evm_setNextBlockTimestamp', [expirationTimestamp + 1000])
        await twamm.executeTWAMMOrders(poolKey)
        await twamm.updateLongTermOrder(poolKey, orderKey0, 0)
        await twamm.updateLongTermOrder(poolKey, orderKey1, 0)

        const newBalance0 = await token0.balanceOf(twamm.address)
        const newBalance1 = await token1.balanceOf(twamm.address)

        const earningsToken0 = await twamm.tokensOwed(poolKey.token0, wallet.address)
        const earningsToken1 = await twamm.tokensOwed(poolKey.token1, wallet.address)

        const expectedSqrtRatioX96 = '1390179360050332758641088620197702593046604939264'

        const finalPriceX96 = (await poolManager.getSlot0(getPoolId(poolKey))).sqrtPriceX96

        expect(finalPriceX96).to.equal(expectedSqrtRatioX96)

        // precision error
        // 7705222119
        // 2879812947
        expect(newBalance0.sub(INITIAL_TOKEN_BALANCE)).to.eq(earningsToken0.add(7705222119))
        expect(newBalance1.sub(INITIAL_TOKEN_BALANCE)).to.eq(earningsToken1.add(2879812947))
      })

      it('swaps to low price (going left)', async () => {
        // increase liquidity so that we are testing not ending at the sqrtSellRatio
        await modifyPositionTest.modifyPosition(poolKey, {
          tickLower: getMinTick(10),
          tickUpper: getMaxTick(10),
          liquidityDelta: '1000000000000000000000000',
        })

        const amountSell0 = BigNumber.from('34025678683638809405905696563977446090000000')
        const amountSell1 = BigNumber.from('100000')

        await inOneBlock(submitTimestamp, async () => {
          await twamm.submitLongTermOrder(poolKey, orderKey0, amountSell0)
          await twamm.submitLongTermOrder(poolKey, orderKey1, amountSell1)
        })

        await ethers.provider.send('evm_setNextBlockTimestamp', [expirationTimestamp + 1000])
        await twamm.executeTWAMMOrders(poolKey)
        await twamm.updateLongTermOrder(poolKey, orderKey0, 0)
        await twamm.updateLongTermOrder(poolKey, orderKey1, 0)

        const newBalance0 = await token0.balanceOf(twamm.address)
        const newBalance1 = await token1.balanceOf(twamm.address)

        const earningsToken0 = await twamm.tokensOwed(poolKey.token0, wallet.address)
        const earningsToken1 = await twamm.tokensOwed(poolKey.token1, wallet.address)

        const expectedSqrtRatioX96 = '4515317890'

        const finalPriceX96 = (await poolManager.getSlot0(getPoolId(poolKey))).sqrtPriceX96

        expect(finalPriceX96).to.equal(expectedSqrtRatioX96)

        // precision error
        // 2504936905
        // 7705222116
        expect(newBalance0.sub(INITIAL_TOKEN_BALANCE)).to.eq(earningsToken0.add(2504936905))
        expect(newBalance1.sub(INITIAL_TOKEN_BALANCE)).to.eq(earningsToken1.add(7705222116))
      })

      it('swaps going right to sqrtSellRatio and does not revert when target tick is an initialized tick', async () => {
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
        await twamm.updateLongTermOrder(poolKey, orderKey0, 0)
        await twamm.updateLongTermOrder(poolKey, orderKey1, 0)

        const newBalance0 = await token0.balanceOf(twamm.address)
        const newBalance1 = await token1.balanceOf(twamm.address)

        const earningsToken0 = await twamm.tokensOwed(poolKey.token0, wallet.address)
        const earningsToken1 = await twamm.tokensOwed(poolKey.token1, wallet.address)

        const expectedPriceX96 = '1441708729548066551791643897157159050890912464896'

        const poolPrice = (await poolManager.getSlot0(getPoolId(poolKey))).sqrtPriceX96

        expect(poolPrice).to.equal(expectedPriceX96)

        // precision error
        // 2944622601
        // 11843735713
        expect(newBalance0.sub(INITIAL_TOKEN_BALANCE)).to.eq(earningsToken0.add(2944622601))
        expect(newBalance1.sub(INITIAL_TOKEN_BALANCE)).to.eq(earningsToken1.add(11843735713))
      })

      it('swaps to to sqrtSellRatio going left and does not error when target tick is initialized tick', async () => {
        const amountSell0 = '34015678683638809405905696563977446090000000'
        const amountSell1 = '100000'

        await inOneBlock(submitTimestamp, async () => {
          await twamm.submitLongTermOrder(poolKey, orderKey0, amountSell0)
          await twamm.submitLongTermOrder(poolKey, orderKey1, amountSell1)
        })

        await ethers.provider.send('evm_setNextBlockTimestamp', [expirationTimestamp + 1000])

        await twamm.executeTWAMMOrders(poolKey)
        await twamm.updateLongTermOrder(poolKey, orderKey0, 0)
        await twamm.updateLongTermOrder(poolKey, orderKey1, 0)

        const newBalance0 = await token0.balanceOf(twamm.address)
        const newBalance1 = await token1.balanceOf(twamm.address)

        const earningsToken0 = await twamm.tokensOwed(poolKey.token0, wallet.address)
        const earningsToken1 = await twamm.tokensOwed(poolKey.token1, wallet.address)

        // sqrtSellRatio
        const expectedPriceX96 = 4295760037

        expect((await poolManager.getSlot0(getPoolId(poolKey))).sqrtPriceX96).to.equal(expectedPriceX96)

        // precision error
        // 3687054054
        // 3249046408
        expect(newBalance0.sub(INITIAL_TOKEN_BALANCE)).to.eq(earningsToken0.add(3687054054))
        expect(newBalance1.sub(INITIAL_TOKEN_BALANCE)).to.eq(earningsToken1.add(3249046408))
      })

      it('swaps to the max price', async () => {
        await modifyPositionTest.modifyPosition(poolKey, {
          tickLower: getMinTick(10),
          tickUpper: getMaxTick(10),
          liquidityDelta: '100000000000000000000000',
        })

        const amountSell0 = '10000'
        const amountSell1 = '540156786836388094059056965639774460900000000'

        await inOneBlock(submitTimestamp, async () => {
          await twamm.submitLongTermOrder(poolKey, orderKey0, amountSell0)
          await twamm.submitLongTermOrder(poolKey, orderKey1, amountSell1)
        })

        await ethers.provider.send('evm_setNextBlockTimestamp', [expirationTimestamp + 1000])

        await twamm.executeTWAMMOrders(poolKey)
        await twamm.updateLongTermOrder(poolKey, orderKey0, 0)
        await twamm.updateLongTermOrder(poolKey, orderKey1, 0)

        const newBalance0 = await token0.balanceOf(twamm.address)
        const newBalance1 = await token1.balanceOf(twamm.address)

        const earningsToken0 = await twamm.tokensOwed(poolKey.token0, wallet.address)
        const earningsToken1 = await twamm.tokensOwed(poolKey.token1, wallet.address)

        // max price w/error
        const expectedPriceX96 = '1461446703485210103287273052203988790139028504576'
        expect((await poolManager.getSlot0(getPoolId(poolKey))).sqrtPriceX96).to.equal(expectedPriceX96)

        // larger precision error in extreme case
        expect(newBalance0.sub(INITIAL_TOKEN_BALANCE)).to.eq(earningsToken0.add(499359406795))
        expect(newBalance1.sub(INITIAL_TOKEN_BALANCE)).to.eq(earningsToken1.add(40099070073))
      })

      it('swaps to the min price', async () => {
        await modifyPositionTest.modifyPosition(poolKey, {
          tickLower: getMinTick(10),
          tickUpper: getMaxTick(10),
          liquidityDelta: '100000000000000000000000',
        })

        const amountSell0 = '540156786836388094059056965639774460900000000'
        const amountSell1 = '10000'

        await inOneBlock(submitTimestamp, async () => {
          await twamm.submitLongTermOrder(poolKey, orderKey0, amountSell0)
          await twamm.submitLongTermOrder(poolKey, orderKey1, amountSell1)
        })

        await ethers.provider.send('evm_setNextBlockTimestamp', [expirationTimestamp + 1000])

        await twamm.executeTWAMMOrders(poolKey)
        await twamm.updateLongTermOrder(poolKey, orderKey0, 0)
        await twamm.updateLongTermOrder(poolKey, orderKey1, 0)

        const newBalance0 = await token0.balanceOf(twamm.address)
        const newBalance1 = await token1.balanceOf(twamm.address)

        const earningsToken0 = await twamm.tokensOwed(poolKey.token0, wallet.address)
        const earningsToken1 = await twamm.tokensOwed(poolKey.token1, wallet.address)

        // min price w/error
        const expectedPriceX96 = '4295128740'
        expect((await poolManager.getSlot0(getPoolId(poolKey))).sqrtPriceX96).to.equal(expectedPriceX96)

        // larger precision error in extreme case
        expect(newBalance0.sub(INITIAL_TOKEN_BALANCE)).to.eq(earningsToken0.add(21934025816))
        expect(newBalance1.sub(INITIAL_TOKEN_BALANCE)).to.eq(earningsToken1.add(499359406802))
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
        submitTimestamp = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 1)
        expirationTimestamp = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 3)
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

          await setNextBlocktime(expirationTimestamp + 1000)
          await twamm.executeTWAMMOrders(poolKey)
          await twamm.updateLongTermOrder(poolKey, orderKey0, 0)
          await twamm.updateLongTermOrder(poolKey, orderKey1, 0)

          const newBalance0 = await token0.balanceOf(twamm.address)
          const newBalance1 = await token1.balanceOf(twamm.address)

          const earningsToken0 = await twamm.tokensOwed(poolKey.token0, wallet.address)
          const earningsToken1 = await twamm.tokensOwed(poolKey.token1, wallet.address)

          const sqrtX96SellRate = encodeSqrtPriceX96(amountSell1, amountSell0)
          expect((await poolManager.getSlot0(getPoolId(poolKey))).sqrtPriceX96).to.equal(sqrtX96SellRate)

          // precision error of 3-4 wei
          expect(newBalance0.sub(INITIAL_TOKEN_BALANCE)).to.eq(earningsToken0.sub(4))
          expect(newBalance1.sub(INITIAL_TOKEN_BALANCE)).to.eq(earningsToken1.sub(3))
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

          await setNextBlocktime(expirationTimestamp + 1000)
          await twamm.executeTWAMMOrders(poolKey)
          await twamm.updateLongTermOrder(poolKey, orderKey0, 0)
          await twamm.updateLongTermOrder(poolKey, orderKey1, 0)

          const newBalance0 = await token0.balanceOf(twamm.address)
          const newBalance1 = await token1.balanceOf(twamm.address)

          const earningsToken0 = await twamm.tokensOwed(poolKey.token0, wallet.address)
          const earningsToken1 = await twamm.tokensOwed(poolKey.token1, wallet.address)

          const sqrtX96SellRate = encodeSqrtPriceX96(amountSell1, amountSell0)
          expect((await poolManager.getSlot0(getPoolId(poolKey))).sqrtPriceX96).to.equal(sqrtX96SellRate)

          // precision error of 7-9 wei
          expect(newBalance0.sub(INITIAL_TOKEN_BALANCE)).to.eq(earningsToken0.sub(9))
          expect(newBalance1.sub(INITIAL_TOKEN_BALANCE)).to.eq(earningsToken1.sub(7))
        })
      })

      describe('with only token0 selling in TWAMM', async () => {
        it('it sets the pool price to the TWAMM sell ratio and twamm hook has token balances equal to earnings', async () => {
          const amountSell0 = expandTo18Decimals(1)

          await inOneBlock(submitTimestamp, async () => {
            await twamm.submitLongTermOrder(poolKey, orderKey0, amountSell0)
          })

          await setNextBlocktime(expirationTimestamp + 1000)
          await twamm.executeTWAMMOrders(poolKey)
          await twamm.updateLongTermOrder(poolKey, orderKey0, 0)

          const newBalance1 = await token1.balanceOf(twamm.address)
          const earningsToken1 = await twamm.tokensOwed(poolKey.token1, wallet.address)

          // precision error of 15 wei
          expect(newBalance1.sub(INITIAL_TOKEN_BALANCE)).to.eq(earningsToken1.sub(15))
        })
      })
    })
  })
})
