import { BigNumber, BigNumberish, Wallet } from 'ethers'
import { ethers, waffle } from 'hardhat'
import { TWAMMTest } from '../typechain/TWAMMTest'
import checkObservationEquals from './shared/checkObservationEquals'
import { expect } from './shared/expect'
import snapshotGasCost from '@uniswap/snapshot-gas-cost'
import { encodeSqrtPriceX96, expandTo18Decimals, MaxUint128 } from './shared/utilities'
import { inOneBlock } from './shared/inOneBlock'
import { TickMathTest } from '../typechain/TickMathTest'

async function mineNextBlock(time: number) {
  await ethers.provider.send('evm_mine', [time])
}

async function setNextBlocktime(time: number) {
  await ethers.provider.send('evm_setNextBlockTimestamp', [time])
}

async function setAutomine(b: boolean) {
  await ethers.provider.send('evm_setAutomine', [b])
}

function nIntervalsFrom(timestamp: number, interval: number, n: number): number {
  return timestamp + (interval - (timestamp % interval)) + interval * (n - 1)
}

function divX96(n: BigNumber): string {
  return (parseInt(n.toString()) / 2 ** 96).toString()
}

type OrderKey = {
  owner: string
  expiration: number
  zeroForOne: boolean
}

type PoolKey = {
  token0: string
  token1: string
  fee: string
  tickSpacing: number
  hooks: string
}

type PoolParams = {
  feeProtocol: number
  sqrtPriceX96: BigNumber
  fee: string
  liquidity: string
  tickSpacing: number
}

const EXPIRATION_INTERVAL = 10_000
const ZERO_ADDR = ethers.constants.AddressZero
const TICK_SPACING = 60
const FEE = '3000'
const MIN_INT128 = BigNumber.from('-170141183460469231731687303715884105728')
const ZERO_FOR_ONE = true
const ONE_FOR_ZERO = false
const POOL_KEY = { token0: ZERO_ADDR, token1: ZERO_ADDR, tickSpacing: TICK_SPACING, fee: FEE, hooks: ZERO_ADDR }

describe('TWAMM', () => {
  let wallet: Wallet, other: Wallet
  let twamm: TWAMMTest
  let tickMath: TickMathTest

  let loadFixture: ReturnType<typeof waffle.createFixtureLoader>
  before('create fixture loader', async () => {
    ;[wallet, other] = await (ethers as any).getSigners()
    loadFixture = waffle.createFixtureLoader([wallet, other])
  })

  before('deploy TickMathTest', async () => {
    const factory = await ethers.getContractFactory('TickMathTest')
    tickMath = (await factory.deploy()) as TickMathTest
  })

  // Finds the time that is numIntervals away from the timestamp.
  // If numIntervals = 0, it finds the closest time.
  function findExpiryTime(timestamp: number, numIntervals: number, interval: number) {
    const nextExpirationTimestamp = timestamp + (interval - (timestamp % interval)) + numIntervals * interval
    return nextExpirationTimestamp
  }

  async function executeTwammAndThen(timestamp: number, poolParams: PoolParams, fn: () => void) {
    await inOneBlock(timestamp, async () => {
      await twamm.executeTWAMMOrders(POOL_KEY, poolParams)
      await fn()
    })
  }

  async function initTicks(ticks: number[], tickSpacing: number): Promise<void> {
    for (const tick of ticks) {
      await twamm.flipTick(tick, tickSpacing)
    }
  }

  beforeEach(async () => {
    twamm = await loadFixture(twammFixture)
  })

  const twammFixture = async () => {
    const twammTestFactory = await ethers.getContractFactory('TWAMMTest')
    return (await twammTestFactory.deploy(EXPIRATION_INTERVAL)) as TWAMMTest
  }

  describe('initialize', () => {
    it('sets the initial state of the twamm', async () => {
      expect(await twamm.lastVirtualOrderTimestamp()).to.equal(0)

      const poolKey = { token0: ZERO_ADDR, token1: ZERO_ADDR, tickSpacing: TICK_SPACING, fee: FEE, hooks: ZERO_ADDR }
      await twamm.initialize()

      expect(await twamm.lastVirtualOrderTimestamp()).to.equal((await ethers.provider.getBlock('latest')).timestamp)
    })
  })

  describe('#isCrossingInitializedTicks', () => {
    let poolParams: PoolParams
    let poolKey: PoolKey
    beforeEach('sets the initial state of the twamm', async () => {
      poolParams = {
        feeProtocol: 0,
        sqrtPriceX96: encodeSqrtPriceX96(1, 1),
        fee: '3000',
        liquidity: '1000000000000000000000000',
        tickSpacing: 60,
      }
      poolKey = { token0: ZERO_ADDR, token1: ZERO_ADDR, tickSpacing: TICK_SPACING, fee: FEE, hooks: ZERO_ADDR }

      expect(await twamm.lastVirtualOrderTimestamp()).to.equal(0)
      await twamm.initialize()
    })

    it('returns false when swapping to the same prices', async () => {
      // set the ticks
      await initTicks([-60, 60], TICK_SPACING)
      const nextPrice = encodeSqrtPriceX96(1, 1)
      const results = await twamm.callStatic.isCrossingInitializedTick(poolParams, poolKey, nextPrice)

      expect(results.initialized).to.be.false
      expect(results.nextTickInit).to.equal(60)
    })

    it('returns true when swapping to the right', async () => {
      // set the ticks
      await initTicks([60], TICK_SPACING)
      // token1 increases
      const nextPrice = encodeSqrtPriceX96(2, 1)
      const results = await twamm.callStatic.isCrossingInitializedTick(poolParams, poolKey, nextPrice)

      expect(results.initialized).to.be.true
      expect(results.nextTickInit).to.equal(60)
    })

    it('returns true when swapping to the left', async () => {
      // set the ticks
      await initTicks([-60], TICK_SPACING)
      // token0 increases
      const nextPrice = encodeSqrtPriceX96(1, 2)
      const results = await twamm.callStatic.isCrossingInitializedTick(poolParams, poolKey, nextPrice)

      expect(results.initialized).to.be.true
      expect(results.nextTickInit).to.equal(-60)
    })

    it('returns false when swapping right and tick is after the target price', async () => {
      const targetTick = 60
      const nextInitializedTick = 120
      const priceAtTick = await tickMath.getSqrtRatioAtTick(targetTick)

      await initTicks([nextInitializedTick], TICK_SPACING)
      const results = await twamm.callStatic.isCrossingInitializedTick(poolParams, poolKey, priceAtTick)

      expect(results.initialized).to.be.false
    })

    it('returns false when swapping right, tick is after the target price, tick is not on tickSpacing', async () => {
      const targetTick = 119
      const nextInitializedTick = 120
      const priceAtTick = await tickMath.getSqrtRatioAtTick(targetTick)

      await initTicks([nextInitializedTick], TICK_SPACING)
      const results = await twamm.callStatic.isCrossingInitializedTick(poolParams, poolKey, priceAtTick)

      expect(results.initialized).to.be.false
    })

    it('returns false when swapping left and tick is after the target price', async () => {
      const targetTick = -60
      const nextInitializedTick = -120
      const priceAtTick = await tickMath.getSqrtRatioAtTick(targetTick)

      await initTicks([nextInitializedTick], TICK_SPACING)
      const results = await twamm.callStatic.isCrossingInitializedTick(poolParams, poolKey, priceAtTick)

      expect(results.initialized).to.be.false
    })

    it('returns false when swapping left, tick is after the target price, tick is not on tickSpacing', async () => {
      const targetTick = -100
      const nextInitializedTick = -120
      const priceAtTick = await tickMath.getSqrtRatioAtTick(targetTick)

      await initTicks([nextInitializedTick], TICK_SPACING)
      const results = await twamm.callStatic.isCrossingInitializedTick(poolParams, poolKey, priceAtTick)

      expect(results.initialized).to.be.false
    })
  })

  describe('#submitLongTermOrder', () => {
    let zeroForOne: boolean
    let owner: string
    let amountIn: BigNumber
    let nonIntervalExpiration: number
    let prevTimeExpiration: number
    let expiration: number

    beforeEach('deploy test twamm', async () => {
      zeroForOne = true
      owner = wallet.address
      amountIn = expandTo18Decimals(1)
      await twamm.initialize()
      const blocktime = (await ethers.provider.getBlock('latest')).timestamp
      nonIntervalExpiration = blocktime
      prevTimeExpiration = findExpiryTime(blocktime, -1, EXPIRATION_INTERVAL)
      // gets the valid expiry time that is 3 intervals out
      expiration = findExpiryTime(blocktime, 3, EXPIRATION_INTERVAL)
    })

    it('reverts if expiry is not on an interval', async () => {
      await expect(twamm.submitLongTermOrder({ zeroForOne, owner, expiration: nonIntervalExpiration }, amountIn)).to.be
        .reverted
    })

    it('reverts if not initialized', async () => {
      const twammUnitialized = await loadFixture(twammFixture)
      await expect(
        twammUnitialized.submitLongTermOrder({ zeroForOne, owner, expiration }, amountIn)
      ).to.be.revertedWith('NotInitialized()')
    })

    it('reverts if expiry is in the past', async () => {
      await expect(
        twamm.submitLongTermOrder({ zeroForOne, owner, expiration: prevTimeExpiration }, amountIn)
      ).to.be.revertedWith(`ExpirationLessThanBlocktime(${prevTimeExpiration})`)
    })

    it('stores the new long term order', async () => {
      const orderKey = { owner, expiration, zeroForOne }
      // TODO: if the twamm is not initialized, should revert
      await twamm.submitLongTermOrder(
        {
          zeroForOne,
          owner,
          expiration,
        },
        amountIn
      )

      const latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
      const sellRate = amountIn.div(expiration - latestTimestamp)

      const newOrder = await twamm.getOrder(orderKey)

      expect(newOrder.exists).to.equal(true)
      expect(newOrder.sellRate).to.equal(sellRate)
    })

    it('increases the sellRate and sellRateEndingPerInterval of the corresponding OrderPool', async () => {
      const orderKey = { owner, expiration, zeroForOne }

      let orderPool = await twamm.getOrderPool(true)
      expect(orderPool.sellRate).to.equal(0)
      expect(await twamm.getOrderPoolSellRateEndingPerInterval(true, expiration)).to.equal(0)

      await twamm.submitLongTermOrder(
        {
          zeroForOne,
          owner,
          expiration,
        },
        amountIn
      )

      const latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
      const sellRate = amountIn.div(expiration - latestTimestamp)

      orderPool = await twamm.getOrderPool(true)
      expect(orderPool.sellRate).to.equal(sellRate)
      expect(await twamm.getOrderPoolSellRateEndingPerInterval(true, expiration)).to.equal(sellRate)
    })

    it('gas', async () => {
      await snapshotGasCost(
        twamm.submitLongTermOrder(
          {
            zeroForOne,
            owner,
            expiration,
          },
          amountIn
        )
      )
    })
  })

  describe('#modifyLongTermOrder', () => {
    let poolKey: PoolKey
    let orderKey: OrderKey
    let interval: number
    let poolParams: PoolParams
    let sellAmount: BigNumber
    let timestampInterval0: number
    let timestampInterval1: number
    let timestampInterval2: number
    let timestampInterval3: number

    beforeEach('deploy test twamm', async () => {
      const owner = wallet.address
      sellAmount = expandTo18Decimals(3)

      poolParams = {
        feeProtocol: 0,
        sqrtPriceX96: encodeSqrtPriceX96(1, 1),
        fee: '3000',
        liquidity: '1000000000000000000000000',
        tickSpacing: 60,
      }

      let latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
      timestampInterval0 = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 1)
      timestampInterval1 = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 2)
      timestampInterval2 = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 3)
      timestampInterval3 = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 4)

      // always start on an interval for consistent timeframes on test runs
      await setNextBlocktime(timestampInterval0)

      poolKey = { token0: ZERO_ADDR, token1: ZERO_ADDR, tickSpacing: TICK_SPACING, fee: FEE, hooks: ZERO_ADDR }
      await twamm.initialize()
      latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp

      orderKey = { owner, expiration: timestampInterval2, zeroForOne: true }

      await executeTwammAndThen(timestampInterval1, poolParams, async () => {
        await twamm.submitLongTermOrder(
          {
            zeroForOne: true,
            owner,
            expiration: timestampInterval2,
          },
          expandTo18Decimals(3)
        )
        await twamm.submitLongTermOrder(
          {
            zeroForOne: false,
            owner,
            expiration: timestampInterval2,
          },
          expandTo18Decimals(3)
        )
      })
      latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
    })

    describe('when a portion of the order is removed', () => {
      beforeEach(async () => {
        // half of the order is now complete - so expandTo18Decimals(1.5) has been sold
        await setNextBlocktime(timestampInterval2 - 5_000)
      })

      it('allows a portion of the order to be removed', async () => {
        const sellRateBefore = (await twamm.getOrder(orderKey)).sellRate
        const poolSellRateBefore = (await twamm.getOrderPool(true)).sellRate

        // given expandTo18Decimals(1.5) has been sold, we are reducing the remaining to sell from 1.5 to 0.5
        // this means the sell rate for the remaining time should divide by 3
        await twamm.modifyLongTermOrder(orderKey, expandTo18Decimals(1).mul(-1))

        const sellRateAfter = (await twamm.getOrder(orderKey)).sellRate
        const poolSellRateAfter = (await twamm.getOrderPool(true)).sellRate

        expect(sellRateBefore).to.be.eq(sellRateAfter.mul(3))
        expect(poolSellRateAfter).to.be.eq(poolSellRateBefore.sub(sellRateBefore).add(sellRateAfter))
      })

      it('revert if more than the order is removed', async () => {
        // given expandTo18Decimals(1.5) has been sold, we try to remove just more than 1.5
        await expect(twamm.modifyLongTermOrder(orderKey, expandTo18Decimals(1.5).add(1).mul(-1))).to.be.revertedWith(
          'InvalidAmountDelta'
        )
      })

      it('does not revert if the exact amount is provided', async () => {
        // given expandTo18Decimals(1.5) has been sold, we try to remove exactly 1.5 more
        await twamm.modifyLongTermOrder(orderKey, expandTo18Decimals(1.5).mul(-1))
        expect(parseInt((await twamm.getOrder(orderKey)).sellRate.toString())).to.be.eq(0)
      })

      it('allows the order size to be increased', async () => {
        const sellRateBefore = (await twamm.getOrder(orderKey)).sellRate
        const poolSellRateBefore = (await twamm.getOrderPool(true)).sellRate

        // given expandTo18Decimals(1.5) has been sold, we are increasing the remaining to sell from 1.5 to 2.5
        // this means the sell rate for the remaining time should be (*5/3)
        await twamm.modifyLongTermOrder(orderKey, expandTo18Decimals(1))

        const sellRateAfter = (await twamm.getOrder(orderKey)).sellRate
        const poolSellRateAfter = (await twamm.getOrderPool(true)).sellRate

        expect(sellRateBefore.mul(5).div(3)).to.be.eq(sellRateAfter)
        expect(poolSellRateAfter).to.be.eq(poolSellRateBefore.sub(sellRateBefore).add(sellRateAfter))
      })

      it('alters an order multiple times', async () => {
        var sellRateBefore = (await twamm.getOrder(orderKey)).sellRate

        // given expandTo18Decimals(1.5) has been sold, we are increasing the remaining to sell from 1.5 to 5
        // this means the sell rate for the remaining time should be (*2)
        await twamm.modifyLongTermOrder(orderKey, expandTo18Decimals(1.5))

        var sellRateAfter = (await twamm.getOrder(orderKey)).sellRate
        expect(sellRateBefore.mul(2)).to.be.eq(sellRateAfter)

        await setNextBlocktime(timestampInterval2 - 2_500)
        // by this timestamp half of the 3 (since last alteration) have been sold
        // we remove 1.2 of the 1.5 remaining, meaning a sell rate of 1/5th
        sellRateBefore = sellRateAfter
        await twamm.modifyLongTermOrder(orderKey, expandTo18Decimals(1.2).mul(-1))
        sellRateAfter = (await twamm.getOrder(orderKey)).sellRate
        expect(sellRateBefore).to.be.eq(sellRateAfter.mul(5))
      })
    })

    describe('when cancelling the remaining order', () => {
      beforeEach(async () => {
        await setNextBlocktime(timestampInterval2 - 5_000)
      })

      it('changes the sell rate of the order to 0', async () => {
        expect(parseInt((await twamm.getOrder(orderKey)).sellRate.toString())).to.be.greaterThan(0)
        await twamm.modifyLongTermOrder(orderKey, MIN_INT128)
        expect(parseInt((await twamm.getOrder(orderKey)).sellRate.toString())).to.be.eq(0)
      })

      it('claims some of the order, then cancels successfully', async () => {
        await twamm.executeTWAMMOrders(POOL_KEY, poolParams)
        await twamm.modifyLongTermOrder(orderKey, MIN_INT128)
        expect((await twamm.getOrder(orderKey)).sellRate).to.eq(0)
      })

      it('updates the unclaimedEarningsFactor to the current earningsFactor accumulator', async () => {
        await twamm.executeTWAMMOrders(POOL_KEY, poolParams)
        await twamm.modifyLongTermOrder(orderKey, MIN_INT128)
        const orderPool = await twamm.getOrderPool(true)
        expect((await twamm.getOrder(orderKey)).unclaimedEarningsFactor).to.eq(orderPool.earningsFactor)
      })

      it('withdraws half the sell amount at midpoint', async () => {
        // update state and cancel the order at the midpoint
        await twamm.executeTWAMMOrders(POOL_KEY, poolParams)

        const amountOut = await twamm.callStatic.modifyLongTermOrder(orderKey, MIN_INT128)
        expect(amountOut).to.equal(sellAmount.div(2))
      })

      it('claims half the earnings at midpoint', async () => {
        await executeTwammAndThen(timestampInterval2 - 5_000, poolParams, async () => {
          await twamm.modifyLongTermOrder(orderKey, MIN_INT128)
        })

        const order = await twamm.getOrder(orderKey)

        expect(order.uncollectedEarningsAmount).to.equal(sellAmount.div(2))
      })
    })

    it('reverts if you cancel after the expiration', async () => {
      await setNextBlocktime(timestampInterval3)
      expect(twamm.modifyLongTermOrder(orderKey, MIN_INT128)).to.be.reverted
    })

    it('gas', async () => {
      await snapshotGasCost(twamm.modifyLongTermOrder(orderKey, MIN_INT128))
    })
  })

  describe('#executeTWAMMOrders', () => {
    let latestTimestamp: number
    let timestampInitialize: number
    let timestampInterval1: number
    let timestampInterval2: number
    let timestampInterval3: number
    let timestampInterval4: number

    beforeEach(async () => {
      latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
      timestampInitialize = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 1)
      timestampInterval1 = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 2)
      timestampInterval2 = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 3)
      timestampInterval3 = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 4)
      timestampInterval4 = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 5)
    })

    describe('both pools selling', () => {
      beforeEach(async () => {
        await setNextBlocktime(timestampInitialize)

        const poolKey = { token0: ZERO_ADDR, token1: ZERO_ADDR, tickSpacing: TICK_SPACING, fee: FEE, hooks: ZERO_ADDR }
        await twamm.initialize()

        await inOneBlock(timestampInterval1, async () => {
          await twamm.submitLongTermOrder(
            {
              zeroForOne: true,
              owner: wallet.address,
              expiration: timestampInterval2,
            },
            expandTo18Decimals(1)
          )

          await twamm.submitLongTermOrder(
            {
              zeroForOne: false,
              owner: wallet.address,
              expiration: timestampInterval3,
            },
            expandTo18Decimals(5)
          )

          await twamm.submitLongTermOrder(
            {
              zeroForOne: false,
              owner: wallet.address,
              expiration: timestampInterval4,
            },
            expandTo18Decimals(2)
          )

          await twamm.submitLongTermOrder(
            {
              zeroForOne: true,
              owner: wallet.address,
              expiration: timestampInterval4,
            },
            expandTo18Decimals(2)
          )
        })
      })

      it('updates all the necessarily earningsFactor intervals', async () => {
        const sqrtPriceX96 = encodeSqrtPriceX96(1, 1)
        const liquidity = '10000000000000000000'
        await setNextBlocktime(timestampInterval4 + 5_000)

        expect(await twamm.getOrderPoolEarningsFactorAtInterval(true, timestampInterval1)).to.eq(0)
        expect(await twamm.getOrderPoolEarningsFactorAtInterval(false, timestampInterval1)).to.eq(0)
        expect(await twamm.getOrderPoolEarningsFactorAtInterval(true, timestampInterval2)).to.eq(0)
        expect(await twamm.getOrderPoolEarningsFactorAtInterval(false, timestampInterval2)).to.eq(0)
        expect(await twamm.getOrderPoolEarningsFactorAtInterval(true, timestampInterval3)).to.eq(0)
        expect(await twamm.getOrderPoolEarningsFactorAtInterval(false, timestampInterval3)).to.eq(0)
        expect(await twamm.getOrderPoolEarningsFactorAtInterval(true, timestampInterval4)).to.eq(0)
        expect(await twamm.getOrderPoolEarningsFactorAtInterval(false, timestampInterval4)).to.eq(0)

        await twamm.executeTWAMMOrders(POOL_KEY, { sqrtPriceX96, liquidity })

        expect(await twamm.getOrderPoolEarningsFactorAtInterval(true, timestampInterval1)).to.be.eq(0)
        expect(await twamm.getOrderPoolEarningsFactorAtInterval(false, timestampInterval1)).to.be.eq(0)
        expect(await twamm.getOrderPoolEarningsFactorAtInterval(true, timestampInterval2)).to.eq(
          '1994006903617166884240785113028529'
        )
        expect(await twamm.getOrderPoolEarningsFactorAtInterval(false, timestampInterval2)).to.eq(
          '1274791212190872404935371267515656'
        )
        expect(await twamm.getOrderPoolEarningsFactorAtInterval(true, timestampInterval3)).to.eq(
          '3371273930125135653759633453292465'
        )
        expect(await twamm.getOrderPoolEarningsFactorAtInterval(false, timestampInterval3)).to.eq(
          '1734117616897553517344907099974480'
        )
        expect(await twamm.getOrderPoolEarningsFactorAtInterval(true, timestampInterval4)).to.eq(
          '4887459849016401416285295160076330'
        )
      })

      it('updates all necessary intervals when block is mined exactly on an interval')

      it('one interval gas', async () => {
        const sqrtPriceX96 = encodeSqrtPriceX96(1, 1)
        const liquidity = '10000000000000000000'
        await setNextBlocktime(timestampInterval2 + 500)
        await snapshotGasCost(twamm.executeTWAMMOrders(POOL_KEY, { sqrtPriceX96, liquidity }))
      })

      it('two intervals gas', async () => {
        const sqrtPriceX96 = encodeSqrtPriceX96(1, 1)
        const liquidity = '10000000000000000000'
        await setNextBlocktime(timestampInterval3 + 5_000)
        await snapshotGasCost(twamm.executeTWAMMOrders(POOL_KEY, { sqrtPriceX96, liquidity }))
      })

      it('three intervals gas', async () => {
        const sqrtPriceX96 = encodeSqrtPriceX96(1, 1)
        const liquidity = '10000000000000000000'
        await setNextBlocktime(timestampInterval4 + 5_000)
        await snapshotGasCost(twamm.executeTWAMMOrders(POOL_KEY, { sqrtPriceX96, liquidity }))
      })
    })

    describe('single pool sell', () => {
      beforeEach(async () => {
        await setNextBlocktime(timestampInterval1 - 1_000)

        const poolKey = { token0: ZERO_ADDR, token1: ZERO_ADDR, tickSpacing: TICK_SPACING, fee: FEE, hooks: ZERO_ADDR }
        await twamm.initialize()

        await inOneBlock(timestampInterval1, async () => {
          await twamm.submitLongTermOrder(
            {
              zeroForOne: true,
              owner: wallet.address,
              expiration: timestampInterval2,
            },
            expandTo18Decimals(1)
          )

          await twamm.submitLongTermOrder(
            {
              zeroForOne: true,
              owner: wallet.address,
              expiration: timestampInterval3,
            },
            expandTo18Decimals(5)
          )

          await twamm.submitLongTermOrder(
            {
              zeroForOne: true,
              owner: wallet.address,
              expiration: timestampInterval4,
            },
            expandTo18Decimals(2)
          )
        })
      })

      it('one interval gas', async () => {
        const sqrtPriceX96 = encodeSqrtPriceX96(1, 1)
        const liquidity = '10000000000000000000'
        await setNextBlocktime(timestampInterval2 + 500)
        await snapshotGasCost(twamm.executeTWAMMOrders(POOL_KEY, { sqrtPriceX96, liquidity }))
      })

      it('two intervals gas', async () => {
        const sqrtPriceX96 = encodeSqrtPriceX96(1, 1)
        const liquidity = '10000000000000000000'
        await setNextBlocktime(timestampInterval3 + 5_000)
        await snapshotGasCost(twamm.executeTWAMMOrders(POOL_KEY, { sqrtPriceX96, liquidity }))
      })

      it('three intervals gas', async () => {
        const sqrtPriceX96 = encodeSqrtPriceX96(1, 1)
        const liquidity = '10000000000000000000'
        await setNextBlocktime(timestampInterval4 + 5_000)
        await snapshotGasCost(twamm.executeTWAMMOrders(POOL_KEY, { sqrtPriceX96, liquidity }))
      })
    })
  })

  describe('#claimEarnings', () => {
    let orderKey: OrderKey
    let counterOrderKey: OrderKey
    const poolParams: PoolParams = {
      feeProtocol: 0,
      sqrtPriceX96: encodeSqrtPriceX96(1, 1),
      fee: '3000',
      tickSpacing: 60,
      liquidity: '14496800315719602540',
    }
    let expiration: number

    beforeEach('create new longTermOrders', async () => {
      const poolKey = { token0: ZERO_ADDR, token1: ZERO_ADDR, tickSpacing: TICK_SPACING, fee: FEE, hooks: ZERO_ADDR }
      await twamm.initialize()

      const timestamp = (await ethers.provider.getBlock('latest')).timestamp
      const startTime = findExpiryTime(timestamp, 1, EXPIRATION_INTERVAL)
      expiration = findExpiryTime(timestamp, 2, EXPIRATION_INTERVAL)
      orderKey = { owner: wallet.address, expiration, zeroForOne: true }
      counterOrderKey = { owner: wallet.address, expiration, zeroForOne: false }
      const ltoParams = { owner: wallet.address, expiration }

      await executeTwammAndThen(startTime, poolParams, async () => {
        await twamm.submitLongTermOrder({ ...ltoParams, zeroForOne: true }, expandTo18Decimals(2))
        await twamm.submitLongTermOrder({ ...ltoParams, zeroForOne: false }, expandTo18Decimals(2))
      })
    })

    it('returns the correct amount if there are claimed but uncollected earnings', async () => {
      // moves time to halfway through the orders
      // calls modify order to cache the earnings as uncollected
      await executeTwammAndThen(expiration - EXPIRATION_INTERVAL / 2, poolParams, async () => {
        // cache uncollected earnings with modify order
        await twamm.modifyLongTermOrder(orderKey, 0)
      })

      const uncollectedEarnings = (await twamm.getOrder(orderKey)).uncollectedEarningsAmount
      expect(uncollectedEarnings).to.be.eq(expandTo18Decimals(1))

      // moves to after the expiry time of the order
      await setNextBlocktime(expiration + 1)
      await twamm.executeTWAMMOrders(POOL_KEY, poolParams)

      // the entirety of the uncollected earnings are claimed
      expect(await twamm.callStatic.claimEarnings(orderKey)).to.equal(expandTo18Decimals(2))
    })

    it('should give correct earnings amount when there are no uncollected earnings', async () => {
      // at precisely the expiration time
      mineNextBlock(expiration)

      await twamm.executeTWAMMOrders(POOL_KEY, poolParams)
      expect(await twamm.callStatic.claimEarnings(orderKey)).to.equal(expandTo18Decimals(2))
    })

    it('claims earnings part of the way through an order', async () => {
      // 3/4 of the way through the order
      const beforeExpiration = expiration - EXPIRATION_INTERVAL / 4
      setNextBlocktime(beforeExpiration)

      await twamm.executeTWAMMOrders(POOL_KEY, poolParams)
      expect(await twamm.callStatic.claimEarnings(orderKey)).to.eq(expandTo18Decimals(1.5))
    })

    it('claims a partial order, changes the order, and claims again at a different rate', async () => {
      const sellRateBefore = (await twamm.getOrder(orderKey)).sellRate

      // moves time to 1/4 through the orders, 1.5 left to sell, 0.5 sold
      // calls modify order which caches the earnings so far
      const oneQuarterTime = expiration - (3 * EXPIRATION_INTERVAL) / 4
      await executeTwammAndThen(oneQuarterTime, poolParams, async () => {
        // cache uncollected earnings and modify order to have 1.8 more, total 3.3 remaining
        // increase the other order so it has something to trade against
        await twamm.modifyLongTermOrder(orderKey, expandTo18Decimals(1.8))
        await twamm.modifyLongTermOrder(counterOrderKey, expandTo18Decimals(1.8))
      })

      const orderAfter = await twamm.getOrder(orderKey)
      expect(orderAfter.sellRate).to.be.eq(sellRateBefore.mul(33).div(15))
      expect(orderAfter.uncollectedEarningsAmount).to.be.eq(expandTo18Decimals(0.5))

      const threeQuarterTime = expiration - EXPIRATION_INTERVAL / 4
      setNextBlocktime(threeQuarterTime)

      // the earnings should be 1/4 of 2 (0.5), uncollected from before
      // plus 2/3 of 3.3 (2.2) from this portion - so a total of 2.7
      await twamm.executeTWAMMOrders(POOL_KEY, poolParams)
      expect(await twamm.callStatic.claimEarnings(orderKey)).to.eq(expandTo18Decimals(2.7))
    })

    it('gas', async () => {
      const afterExpiration = orderKey.expiration + EXPIRATION_INTERVAL / 2

      mineNextBlock(afterExpiration)

      await snapshotGasCost(twamm.claimEarnings(orderKey))
    })
  })

  describe('end-to-end simulation', async () => {
    describe('execute both pools selling', () => {
      it('distributes correct rewards on equal trading pools at a price of 1', async () => {
        const sqrtPriceX96 = encodeSqrtPriceX96(1, 1)
        const liquidity = '1000000000000000000000000'
        const fee = '3000'
        const tickSpacing = 60
        const feeProtocol = 0

        const poolParams = { feeProtocol, sqrtPriceX96, liquidity, fee, tickSpacing }

        const poolKey = { token0: ZERO_ADDR, token1: ZERO_ADDR, tickSpacing: TICK_SPACING, fee: FEE, hooks: ZERO_ADDR }
        await twamm.initialize()

        const latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
        const timestampInterval1 = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 1)
        const timestampInterval2 = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 3)
        const timestampInterval3 = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 4)

        const halfSellAmount = expandTo18Decimals(2.5)
        const fullSellAmount = expandTo18Decimals(5)
        const fullSellRate = fullSellAmount.div(timestampInterval2 - timestampInterval1)

        const owner = wallet.address
        const expiration = timestampInterval2
        const orderKey1 = { owner, expiration, zeroForOne: true }
        const orderKey2 = { owner, expiration, zeroForOne: true }
        const orderKey3 = { owner, expiration, zeroForOne: false }

        expect((await twamm.getOrderPool(true)).sellRate).to.eq(0)
        expect((await twamm.getOrderPool(false)).sellRate).to.eq(0)

        await executeTwammAndThen(timestampInterval1, poolParams, async () => {
          await twamm.submitLongTermOrder(
            {
              zeroForOne: true,
              owner,
              expiration: timestampInterval2,
            },
            halfSellAmount
          )
          await twamm.submitLongTermOrder(
            {
              zeroForOne: true,
              owner: other.address,
              expiration: timestampInterval2,
            },
            halfSellAmount
          )
          await twamm.submitLongTermOrder(
            {
              zeroForOne: false,
              owner,
              expiration: timestampInterval2,
            },
            fullSellAmount
          )
        })

        expect((await twamm.getOrderPool(true)).sellRate).to.eq(fullSellRate)
        expect((await twamm.getOrderPool(false)).sellRate).to.eq(fullSellRate)
        expect((await twamm.getOrderPool(true)).earningsFactor).to.eq('0')
        expect((await twamm.getOrderPool(false)).earningsFactor).to.eq('0')

        await setNextBlocktime(timestampInterval2)
        await twamm.executeTWAMMOrders(POOL_KEY, poolParams)

        expect((await twamm.callStatic.getOrderPool(true)).sellRate).to.eq('0')
        expect((await twamm.callStatic.getOrderPool(false)).sellRate).to.eq('0')
        expect((await twamm.callStatic.getOrderPool(true)).earningsFactor).to.eq('1584563250285286751870879006720000')
        expect((await twamm.callStatic.getOrderPool(false)).earningsFactor).to.eq('1584563250285286751870879006720000')

        await setNextBlocktime(timestampInterval3)
        await twamm.executeTWAMMOrders(POOL_KEY, poolParams)

        expect((await twamm.getOrderPool(true)).sellRate).to.eq('0')
        expect((await twamm.getOrderPool(false)).sellRate).to.eq('0')
        expect((await twamm.getOrderPool(true)).earningsFactor).to.eq('1584563250285286751870879006720000')
        expect((await twamm.getOrderPool(false)).earningsFactor).to.eq('1584563250285286751870879006720000')

        expect((await twamm.getOrder(orderKey1)).sellRate).to.eq(halfSellAmount.div(20_000))
        expect((await twamm.getOrder(orderKey2)).sellRate).to.eq(halfSellAmount.div(20_000))
        expect((await twamm.getOrder(orderKey3)).sellRate).to.eq(fullSellAmount.div(20_000))

        expect(await twamm.callStatic.claimEarnings(orderKey1)).to.eq(halfSellAmount)
        expect(await twamm.callStatic.claimEarnings(orderKey2)).to.eq(halfSellAmount)
        expect(await twamm.callStatic.claimEarnings(orderKey3)).to.eq(fullSellAmount)
      })
    })

    describe('single pool sell tests', async () => {
      let blocktime: number
      let startTime: number
      let halfTime: number
      let expiryTime: number
      let orderKey: OrderKey

      const zeroForOne = true
      const sqrtPriceX96 = encodeSqrtPriceX96(1, 1)
      const liquidity = '1000000000000000000000000'
      const fee = '3000'
      const tickSpacing = 60
      const feeProtocol = 0
      const poolParams = { feeProtocol, sqrtPriceX96, liquidity, fee, tickSpacing }

      const error = 5
      const fullSellAmount = expandTo18Decimals(5)
      const halfSellAmount = fullSellAmount.div(2)
      const halfSellAmountUnderError = halfSellAmount.sub(halfSellAmount.div(error))
      const halfSellAmountOverError = halfSellAmount.add(halfSellAmount.div(error))
      const fullSellAmountUnderError = fullSellAmount.sub(fullSellAmount.div(error))
      const fullSellAmountOverError = fullSellAmount.add(fullSellAmount.div(error))

      beforeEach('submit a single long term order', async () => {
        const poolKey = { token0: ZERO_ADDR, token1: ZERO_ADDR, tickSpacing: TICK_SPACING, fee: FEE, hooks: ZERO_ADDR }
        blocktime = (await ethers.provider.getBlock('latest')).timestamp

        startTime = findExpiryTime(blocktime, 1, EXPIRATION_INTERVAL)
        halfTime = findExpiryTime(blocktime, 2, EXPIRATION_INTERVAL)
        expiryTime = findExpiryTime(blocktime, 3, EXPIRATION_INTERVAL)

        await setNextBlocktime(startTime - 1_000)
        await twamm.initialize()

        orderKey = { owner: wallet.address, expiration: expiryTime, zeroForOne: true }

        await executeTwammAndThen(startTime, poolParams, async () => {
          await twamm.submitLongTermOrder(
            {
              zeroForOne,
              owner: wallet.address,
              expiration: expiryTime,
            },
            fullSellAmount
          )
        })

        const expectedSellRate = fullSellAmount.div(expiryTime - startTime)
        const actualSellRate = (await twamm.getOrder(orderKey)).sellRate
      })

      describe('when an order is midway complete', () => {
        it('claims half the earnings', async () => {
          await setNextBlocktime(halfTime)
          twamm.executeTWAMMOrders(POOL_KEY, poolParams)
          expect(await twamm.callStatic.claimEarnings(orderKey)).to.eq('2499993750015624960')
        })

        it('keeps the sell rate the same', async () => {
          expect((await twamm.getOrder(orderKey)).sellRate).to.eq('250000000000000')
          await setNextBlocktime(halfTime)
          twamm.executeTWAMMOrders(POOL_KEY, poolParams)
          await twamm.claimEarnings(orderKey)
          expect((await twamm.getOrder(orderKey)).sellRate).to.eq('250000000000000')
        })
      })

      describe('when an order is complete', () => {
        it('claims the correct earnings', async () => {
          await setNextBlocktime(expiryTime + 1)
          twamm.executeTWAMMOrders(POOL_KEY, poolParams)
          expect(await twamm.callStatic.claimEarnings(orderKey)).to.eq('4999975000124999375')
        })

        it('sets the sell rate to 0', async () => {
          await setNextBlocktime(expiryTime + 1)
          twamm.executeTWAMMOrders(POOL_KEY, poolParams)
          await twamm.claimEarnings(orderKey)
          expect((await twamm.getOrder(orderKey)).sellRate).to.eq(0)
        })
      })

      it('should update state exactly to the expiry', async () => {
        setNextBlocktime(expiryTime)
        await twamm.executeTWAMMOrders(POOL_KEY, poolParams)
        const blocktime = (await ethers.provider.getBlock('latest')).timestamp
        const newExpiry = findExpiryTime(blocktime, 3, EXPIRATION_INTERVAL)
        await twamm.submitLongTermOrder(
          {
            zeroForOne: false,
            owner: wallet.address,
            expiration: newExpiry,
          },
          fullSellAmount
        )
        const orderPool0 = await twamm.getOrderPool(true)
        const orderPool1 = await twamm.getOrderPool(false)
        expect(orderPool0.sellRate.toNumber()).to.eq(0)
        expect(orderPool1.sellRate.toNumber()).to.be.greaterThan(0)
      })

      it('gas zeroForOne=true', async () => {
        mineNextBlock(expiryTime)
        await snapshotGasCost(twamm.executeTWAMMOrders(POOL_KEY, poolParams))
      })

      it('gas zeroForOne=false', async () => {
        mineNextBlock(expiryTime)
        blocktime = (await ethers.provider.getBlock('latest')).timestamp
        const newExpiryTime = findExpiryTime(blocktime, 3, EXPIRATION_INTERVAL)
        await twamm.executeTWAMMOrders(POOL_KEY, poolParams)
        await twamm.submitLongTermOrder(
          {
            zeroForOne: false,
            owner: wallet.address,
            expiration: newExpiryTime,
          },
          fullSellAmount
        )
        mineNextBlock(newExpiryTime)
        await snapshotGasCost(twamm.executeTWAMMOrders(POOL_KEY, poolParams))
      })
    })
  })
})
