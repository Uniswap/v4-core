import { BigNumber, BigNumberish, Wallet } from 'ethers'
import { ethers, waffle } from 'hardhat'
import { TWAMMTest } from '../typechain/TWAMMTest'
import checkObservationEquals from './shared/checkObservationEquals'
import { expect } from './shared/expect'
import snapshotGasCost from '@uniswap/snapshot-gas-cost'
import { encodeSqrtPriceX96, MaxUint128 } from './shared/utilities'
import { inOneBlock } from './shared/inOneBlock'

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

function toWei(n: string): BigNumber {
  return ethers.utils.parseEther(n)
}

function divX96(n: BigNumber): string {
  return (parseInt(n.toString()) / 2 ** 96).toString()
}

type OrderKey = {
  owner: string
  expiration: number
  zeroForOne: boolean
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

describe('TWAMM', () => {
  let wallet: Wallet, other: Wallet
  let twamm: TWAMMTest

  let loadFixture: ReturnType<typeof waffle.createFixtureLoader>
  before('create fixture loader', async () => {
    ;[wallet, other] = await (ethers as any).getSigners()
    loadFixture = waffle.createFixtureLoader([wallet, other])
  })

  // Finds the time that is numIntervals away from the timestamp.
  // If numIntervals = 0, it finds the closest time.
  function findExpiryTime(timestamp: number, numIntervals: number, interval: number) {
    const nextExpirationTimestamp = timestamp + (interval - (timestamp % interval)) + numIntervals * interval
    return nextExpirationTimestamp
  }

  async function executeTwammAndThen(timestamp: number, poolParams: PoolParams, fn: () => void) {
    await inOneBlock(timestamp, async () => {
      await twamm.executeTWAMMOrders(poolParams)
      await fn()
    })
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
      expect((await twamm.twamm()).lastVirtualOrderTimestamp).to.equal(0)

      const poolKey = { token0: ZERO_ADDR, token1: ZERO_ADDR, tickSpacing: TICK_SPACING, fee: FEE, hooks: ZERO_ADDR }
      await twamm.initialize(poolKey)

      expect((await twamm.twamm()).lastVirtualOrderTimestamp).to.equal(
        (await ethers.provider.getBlock('latest')).timestamp
      )
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
      amountIn = toWei('1')
      const poolKey = { token0: ZERO_ADDR, token1: ZERO_ADDR, tickSpacing: TICK_SPACING, fee: FEE, hooks: ZERO_ADDR }
      await twamm.initialize(poolKey)
      const blocktime = (await ethers.provider.getBlock('latest')).timestamp
      nonIntervalExpiration = blocktime
      prevTimeExpiration = findExpiryTime(blocktime, -1, 10000)
      // gets the valid expiry time that is 3 intervals out
      expiration = findExpiryTime(blocktime, 3, EXPIRATION_INTERVAL)
    })

    it('reverts if expiry is not on an interval', async () => {
      await expect(twamm.submitLongTermOrder({ zeroForOne, owner, amountIn, expiration: nonIntervalExpiration })).to.be
        .reverted
    })

    it('reverts if not initialized', async () => {
      const twammUnitialized = await loadFixture(twammFixture)
      await expect(
        twammUnitialized.submitLongTermOrder({ zeroForOne, owner, amountIn, expiration })
      ).to.be.revertedWith('NotInitialized()')
    })

    it('reverts if expiry is in the past', async () => {
      await expect(
        twamm.submitLongTermOrder({ zeroForOne, owner, amountIn, expiration: prevTimeExpiration })
      ).to.be.revertedWith(`ExpirationLessThanBlocktime(${prevTimeExpiration})`)
    })

    it('stores the new long term order', async () => {
      const orderKey = { owner, expiration, zeroForOne }
      // TODO: if the twamm is not initialized, should revert
      await twamm.submitLongTermOrder({
        zeroForOne,
        owner,
        amountIn,
        expiration,
      })

      const latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
      const sellRate = amountIn.div(expiration - latestTimestamp)

      const newOrder = await twamm.getOrder(orderKey)

      expect(newOrder.sellTokenIndex).to.equal(0)
      expect(newOrder.sellRate).to.equal(sellRate)
      expect(newOrder.expiration).to.equal(expiration)
    })

    it('increases the sellRate and sellRateEndingPerInterval of the corresponding OrderPool', async () => {
      const orderKey = { owner, expiration, zeroForOne }

      let orderPool = await twamm.getOrderPool(0)
      expect(orderPool.sellRate).to.equal(0)
      expect(await twamm.getOrderPoolSellRateEndingPerInterval(0, expiration)).to.equal(0)

      await twamm.submitLongTermOrder({
        zeroForOne,
        owner,
        amountIn,
        expiration,
      })

      const latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
      const sellRate = amountIn.div(expiration - latestTimestamp)

      orderPool = await twamm.getOrderPool(0)
      expect(orderPool.sellRate).to.equal(sellRate)
      expect(await twamm.getOrderPoolSellRateEndingPerInterval(0, expiration)).to.equal(sellRate)
    })

    it('gas', async () => {
      await snapshotGasCost(
        twamm.submitLongTermOrder({
          zeroForOne,
          owner,
          amountIn,
          expiration,
        })
      )
    })
  })

  describe('#modifyLongTermOrder', () => {
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
      sellAmount = toWei('3')

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
      await ethers.provider.send('evm_setNextBlockTimestamp', [timestampInterval0])

      const poolKey = { token0: ZERO_ADDR, token1: ZERO_ADDR, tickSpacing: TICK_SPACING, fee: FEE, hooks: ZERO_ADDR }
      await twamm.initialize(poolKey)

      orderKey = { owner, expiration: timestampInterval2, zeroForOne: true }

      await executeTwammAndThen(timestampInterval1, poolParams, async () => {
        await twamm.submitLongTermOrder({
          zeroForOne: true,
          owner,
          amountIn: toWei('3'),
          expiration: timestampInterval2,
        })
        await twamm.submitLongTermOrder({
          zeroForOne: false,
          owner,
          amountIn: toWei('3'),
          expiration: timestampInterval2,
        })
      })
    })

    describe('when cancelling the remaining order', () => {
      beforeEach(async () => {
        await ethers.provider.send('evm_setNextBlockTimestamp', [timestampInterval2 - 5_000])
      })

      it('changes the sell rate of the order to 0', async () => {
        expect(parseInt((await twamm.getOrder(orderKey)).sellRate.toString())).to.be.greaterThan(0)
        await twamm.modifyLongTermOrder(orderKey, MIN_INT128)
        expect(parseInt((await twamm.getOrder(orderKey)).sellRate.toString())).to.be.eq(0)
      })

      it('claims some of the order, then cancels successfully', async () => {
        await twamm.executeTWAMMOrders(poolParams)
        await twamm.modifyLongTermOrder(orderKey, MIN_INT128)
        expect((await twamm.getOrder(orderKey)).sellRate).to.eq(0)
      })

      it('updates the unclaimedEarningsFactor to the current earningsFactor accumulator', async () => {
        await twamm.executeTWAMMOrders(poolParams)
        await twamm.modifyLongTermOrder(orderKey, MIN_INT128)
        const orderPool = await twamm.getOrderPool(0)
        expect((await twamm.getOrder(orderKey)).unclaimedEarningsFactor).to.eq(orderPool.earningsFactor)
      })

      it('claims half the amount at midpoint', async () => {
        // update state and cancel the order at the midpoint
        await ethers.provider.send('evm_setNextBlockTimestamp', [timestampInterval2 - 5_000])
        await twamm.executeTWAMMOrders(poolParams)

        const results = await twamm.callStatic.modifyLongTermOrder(orderKey, MIN_INT128)
        expect(results.amountOut0).to.equal(sellAmount.div(2))
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
      await ethers.provider.send('evm_setNextBlockTimestamp', [timestampInterval3])
      expect(twamm.modifyLongTermOrder(orderKey, MIN_INT128)).to.be.reverted
    })

    it('gas', async () => {
      await snapshotGasCost(twamm.modifyLongTermOrder(orderKey, MIN_INT128))
    })
  })

  describe('#executeTWAMMOrders', () => {
    let latestTimestamp: number
    let timestampInterval1: number
    let timestampInterval2: number
    let timestampInterval3: number
    let timestampInterval4: number

    beforeEach(async () => {
      latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
      await ethers.provider.send('evm_setNextBlockTimestamp', [nIntervalsFrom(latestTimestamp, 10_000, 1)])

      const poolKey = { token0: ZERO_ADDR, token1: ZERO_ADDR, tickSpacing: TICK_SPACING, fee: FEE, hooks: ZERO_ADDR }
      await twamm.initialize(poolKey)

      latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
      timestampInterval1 = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 1)
      timestampInterval2 = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 2)
      timestampInterval3 = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 3)
      timestampInterval4 = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 4)

      await inOneBlock(timestampInterval1, async () => {
        await twamm.submitLongTermOrder({
          zeroForOne: true,
          owner: wallet.address,
          amountIn: toWei('1'),
          expiration: timestampInterval2,
        })

        await twamm.submitLongTermOrder({
          zeroForOne: false,
          owner: wallet.address,
          amountIn: toWei('5'),
          expiration: timestampInterval3,
        })

        // set two more expiry's so its never 0, logic isn't there yet
        await twamm.submitLongTermOrder({
          zeroForOne: false,
          owner: wallet.address,
          amountIn: toWei('2'),
          expiration: timestampInterval4,
        })

        await twamm.submitLongTermOrder({
          zeroForOne: true,
          owner: wallet.address,
          amountIn: toWei('2'),
          expiration: timestampInterval4,
        })
      })
    })

    it('updates all the necessarily intervals', async () => {
      const sqrtPriceX96 = encodeSqrtPriceX96(1, 1)
      const liquidity = '10000000000000000000'
      const fee = 3000
      const tickSpacing = 60
      await ethers.provider.send('evm_setNextBlockTimestamp', [timestampInterval3 + 5_000])

      expect(await twamm.getOrderPoolEarningsFactorAtInterval(0, timestampInterval1)).to.eq(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(1, timestampInterval1)).to.eq(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(0, timestampInterval2)).to.eq(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(1, timestampInterval2)).to.eq(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(0, timestampInterval3)).to.eq(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(1, timestampInterval3)).to.eq(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(0, timestampInterval4)).to.eq(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(1, timestampInterval4)).to.eq(0)

      await twamm.executeTWAMMOrders({ sqrtPriceX96, liquidity })

      expect(await twamm.getOrderPoolEarningsFactorAtInterval(0, timestampInterval1)).to.be.eq(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(1, timestampInterval1)).to.be.eq(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(0, timestampInterval2)).to.be.gt(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(1, timestampInterval2)).to.be.gt(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(0, timestampInterval3)).to.be.gt(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(1, timestampInterval3)).to.be.gt(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(0, timestampInterval4)).to.eq(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(1, timestampInterval4)).to.eq(0)
    })

    it('updates all necessary intervals when block is mined exactly on an interval')

    // TODO: intermittent gas failure. due to timestamps?
    it('gas', async () => {
      const sqrtPriceX96 = encodeSqrtPriceX96(1, 1)
      const liquidity = '10000000000000000000'
      const fee = 3000
      const tickSpacing = 60
      await ethers.provider.send('evm_setNextBlockTimestamp', [timestampInterval3 + 5_000])
      await snapshotGasCost(twamm.executeTWAMMOrders({ sqrtPriceX96, liquidity }))
    })

    describe('when TWAMM pushes pool to min/max price', () => {
      describe('when a single pool is trading', () => {
        //  Will essentially buy the most it can from the pool on the very first
        // update and on subsequent claims, it claims nothing bc there is nothing left in the pool.
        let blocktime: number
        let submission: number
        let midPointTime: number
        let expiration: number

        const interval = 10_000

        const sqrtPriceX96 = encodeSqrtPriceX96(1, 1)
        const liquidity = '1000000'
        // seems like the min amount that can be left in the pool is 1
        const maxPoolSell = '999999'
        const fee = '3000'
        const tickSpacing = 60
        const poolParams = { sqrtPriceX96, liquidity, fee, tickSpacing }

        const amountIn = toWei('4')
        const zeroForOne = true
        const halfAmount = amountIn.div(2)

        beforeEach('Initialize a single pool sell', async () => {
          const poolKey = {
            token0: ZERO_ADDR,
            token1: ZERO_ADDR,
            tickSpacing: TICK_SPACING,
            fee: FEE,
            hooks: ZERO_ADDR,
          }
          blocktime = (await ethers.provider.getBlock('latest')).timestamp
          submission = nIntervalsFrom(blocktime, interval, 1)

          midPointTime = nIntervalsFrom(blocktime, interval, 3)
          expiration = nIntervalsFrom(blocktime, interval, 5)

          await twamm.initialize(poolKey)

          const zeroForOneOrder = { zeroForOne, owner: wallet.address, amountIn, expiration }
          await setAutomine(false)
          await twamm.executeTWAMMOrders(poolParams)
          await twamm.submitLongTermOrder(zeroForOneOrder)
          await mineNextBlock(submission)
          await setAutomine(true)
        })

        it('sells the full amount at the first update', async () => {
          const firstInterval = nIntervalsFrom(blocktime, interval, 2)
          // Set the time somewhere between submission and the first full interval.
          await setAutomine(false)
          await twamm.executeTWAMMOrders(poolParams)
          await mineNextBlock((submission + firstInterval) / 2)
          await setAutomine(true)
          const results = await twamm.callStatic.claimEarnings({ owner: wallet.address, expiration, zeroForOne })
          expect(results.earningsAmount.toString()).to.eq(maxPoolSell)
        })

        it('sells the full amount at the expiry', async () => {
          await setNextBlocktime(expiration)
          await twamm.executeTWAMMOrders(poolParams)

          const results = await twamm.callStatic.claimEarnings({ owner: wallet.address, expiration, zeroForOne })
          // still expecting to get less than half the amount since the rate is so bad
          expect(results.earningsAmount).to.be.lt(halfAmount)
          expect(results.earningsAmount).to.be.eq(maxPoolSell)
        })
      })

      describe('when both pools are trading', () => {
        let blocktime: number
        let timestamp1: number
        let timestamp2: number
        let timestamp3: number

        const interval = 10_000

        const sqrtPriceX96 = encodeSqrtPriceX96(1, 1)
        const liquidity = '100000'
        const fee = '3000'
        const tickSpacing = 60

        const poolParams = { sqrtPriceX96, liquidity, fee, tickSpacing }

        const amountIn = toWei('4')
        const zeroForOne = true
        const halfAmount = amountIn.div(2)

        beforeEach('Initialize two orders', async () => {
          const poolKey = {
            token0: ZERO_ADDR,
            token1: ZERO_ADDR,
            tickSpacing: TICK_SPACING,
            fee: FEE,
            hooks: ZERO_ADDR,
          }
          blocktime = (await ethers.provider.getBlock('latest')).timestamp
          timestamp1 = nIntervalsFrom(blocktime, interval, 1)
          timestamp2 = nIntervalsFrom(blocktime, interval, 3)
          timestamp3 = nIntervalsFrom(blocktime, interval, 5)

          await twamm.initialize(poolKey)
          await twamm.executeTWAMMOrders(poolParams)

          const zeroForOneOrder = { zeroForOne, owner: wallet.address, amountIn, expiration: timestamp3 }
          const oneForZeroOrder = {
            zeroForOne: false,
            owner: wallet.address,
            amountIn: halfAmount,
            expiration: timestamp3,
          }
          await ethers.provider.send('evm_setNextBlockTimestamp', [timestamp1])
          await twamm.submitLongTermOrder(zeroForOneOrder)
          await twamm.submitLongTermOrder(oneForZeroOrder)
        })

        // TODO: update calculations for earnings when we reach a max or min price
        it.skip('should handle the overflow', async () => {
          await ethers.provider.send('evm_mine', [timestamp3])
          await twamm.executeTWAMMOrders(poolParams)
          await twamm.callStatic.claimEarnings({
            owner: wallet.address,
            expiration: timestamp3,
            zeroForOne,
          })
          await twamm.callStatic.claimEarnings({
            owner: wallet.address,
            expiration: timestamp3,
            zeroForOne: false,
          })
        })
      })
    })
  })

  describe('#claimEarnings', () => {
    let orderKey: OrderKey
    const mockTicks = {}
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
      await twamm.initialize(poolKey)

      const timestamp = (await ethers.provider.getBlock('latest')).timestamp
      const startTime = findExpiryTime(timestamp, 1, EXPIRATION_INTERVAL)
      expiration = findExpiryTime(timestamp, 2, EXPIRATION_INTERVAL)
      orderKey = { owner: wallet.address, expiration, zeroForOne: true }
      const ltoParams = { owner: wallet.address, expiration, amountIn: toWei('2') }

      await executeTwammAndThen(startTime, poolParams, async () => {
        await twamm.submitLongTermOrder({ ...ltoParams, zeroForOne: true })
        await twamm.submitLongTermOrder({ ...ltoParams, zeroForOne: false })
      })
    })

    it('returns the correct amount if there are claimed but uncollected earnings', async () => {
      await executeTwammAndThen(expiration - EXPIRATION_INTERVAL / 2, poolParams, async () => {
        // cache uncollected earnings with modify order
        await twamm.modifyLongTermOrder(orderKey, 0)
      })

      await setNextBlocktime(expiration + 20_000)
      await twamm.executeTWAMMOrders(poolParams)

      const result = await twamm.callStatic.claimEarnings(orderKey)
      expect(result.earningsAmount).to.equal(toWei('2'))
    })

    it('should give correct earnings amount and have no unclaimed earnings', async () => {
      const afterExpiration = expiration + EXPIRATION_INTERVAL / 2
      expect(afterExpiration).to.be.greaterThan(expiration)

      mineNextBlock(afterExpiration)

      await twamm.executeTWAMMOrders(poolParams)
      const result = await twamm.callStatic.claimEarnings(orderKey)

      const earningsAmount: BigNumber = result.earningsAmount
      const unclaimed: BigNumber = result.unclaimedEarningsAmount

      // TODO: calculate expected earningsAmount
      expect(parseInt(earningsAmount.toString())).to.be.greaterThan(0)
      expect(parseInt(unclaimed.toString())).to.eq(0)
    })

    it('should give correct earningsAmount and have some unclaimed earnings', async () => {
      const expiration = (await twamm.getOrder(orderKey)).expiration.toNumber()
      const beforeExpiration = expiration - EXPIRATION_INTERVAL / 2

      mineNextBlock(beforeExpiration)

      await twamm.executeTWAMMOrders(poolParams)
      const result = await twamm.callStatic.claimEarnings(orderKey)

      const earningsAmount: BigNumber = result.earningsAmount
      const unclaimed: BigNumber = result.unclaimedEarningsAmount

      // TODO: calculate expected earningsAmount
      expect(parseInt(earningsAmount.toString())).to.be.greaterThan(0)
      expect(parseInt(unclaimed.toString())).to.be.greaterThan(0)
    })
    // TODO: test an order that expires after only 1 interval and claim in between

    it('gas', async () => {
      const expiration = (await twamm.getOrder(orderKey)).expiration.toNumber()
      const afterExpiration = expiration + EXPIRATION_INTERVAL / 2

      mineNextBlock(afterExpiration)

      await snapshotGasCost(twamm.claimEarnings(orderKey))
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
    const fullSellAmount = toWei('5')
    const halfSellAmount = fullSellAmount.div(2)
    const halfSellAmountUnderError = halfSellAmount.sub(halfSellAmount.div(error))
    const halfSellAmountOverError = halfSellAmount.add(halfSellAmount.div(error))
    const fullSellAmountUnderError = fullSellAmount.sub(fullSellAmount.div(error))
    const fullSellAmountOverError = fullSellAmount.add(fullSellAmount.div(error))

    beforeEach('submit a single long term order', async () => {
      const poolKey = { token0: ZERO_ADDR, token1: ZERO_ADDR, tickSpacing: TICK_SPACING, fee: FEE, hooks: ZERO_ADDR }
      await twamm.initialize(poolKey)

      blocktime = (await ethers.provider.getBlock('latest')).timestamp
      startTime = findExpiryTime(blocktime, 1, EXPIRATION_INTERVAL)
      halfTime = findExpiryTime(blocktime, 2, EXPIRATION_INTERVAL)
      expiryTime = findExpiryTime(blocktime, 3, EXPIRATION_INTERVAL)

      orderKey = { owner: wallet.address, expiration: expiryTime, zeroForOne: true }

      await executeTwammAndThen(startTime, poolParams, async () => {
        await twamm.submitLongTermOrder({
          zeroForOne,
          owner: wallet.address,
          amountIn: fullSellAmount,
          expiration: expiryTime,
        })
      })

      blocktime = (await ethers.provider.getBlock('latest')).timestamp
      const expectedSellRate = fullSellAmount.div(expiryTime - blocktime)
      const actualSellRate = (await twamm.getOrder(orderKey)).sellRate

      expect(expectedSellRate).to.be.eq(actualSellRate)
    })

    it('claims an order midway through a single pool sell', async () => {
      await ethers.provider.send('evm_setNextBlockTimestamp', [halfTime])
      twamm.executeTWAMMOrders(poolParams)
      const results = await twamm.callStatic.claimEarnings(orderKey)

      const earningsAmount = results.earningsAmount
      const unclaimedAmount = results.unclaimedEarningsAmount

      expect(parseInt(earningsAmount.toString())).to.be.greaterThanOrEqual(
        parseInt(halfSellAmountUnderError.toString())
      )
      expect(parseInt(earningsAmount.toString())).to.be.lessThanOrEqual(parseInt(halfSellAmountOverError.toString()))
      expect(parseInt(unclaimedAmount.toString())).to.be.greaterThanOrEqual(
        parseInt(halfSellAmountUnderError.toString())
      )
      expect(parseInt(unclaimedAmount.toString())).to.be.lessThanOrEqual(parseInt(halfSellAmountOverError.toString()))
    })

    it('claims an order after a full single pool sell', async () => {
      await ethers.provider.send('evm_setNextBlockTimestamp', [expiryTime])

      twamm.executeTWAMMOrders(poolParams)
      const results = await twamm.callStatic.claimEarnings(orderKey)

      const earningsAmount = results.earningsAmount
      const unclaimedAmount = results.unclaimedEarningsAmount

      expect(parseInt(earningsAmount.toString())).to.be.greaterThanOrEqual(
        parseInt(fullSellAmountUnderError.toString())
      )
      expect(parseInt(earningsAmount.toString())).to.be.lessThanOrEqual(parseInt(fullSellAmountOverError.toString()))
      // There should be no unclaimed since we've sold the full amount.
      expect(parseInt(unclaimedAmount.toString())).to.be.eq(0)
    })
    it('should update state exactly to the expiry', async () => {
      setNextBlocktime(expiryTime)
      await twamm.executeTWAMMOrders(poolParams)
      const blocktime = (await ethers.provider.getBlock('latest')).timestamp
      const newExpiry = findExpiryTime(blocktime, 3, EXPIRATION_INTERVAL)
      await twamm.submitLongTermOrder({
        zeroForOne: false,
        owner: wallet.address,
        amountIn: fullSellAmount,
        expiration: newExpiry,
      })
      const orderPool0 = await twamm.getOrderPool(0)
      const orderPool1 = await twamm.getOrderPool(1)
      expect(orderPool0.sellRate.toNumber()).to.eq(0)
      expect(orderPool1.sellRate.toNumber()).to.be.greaterThan(0)
    })

    it('gas', async () => {
      mineNextBlock(expiryTime)
      await snapshotGasCost(twamm.executeTWAMMOrders(poolParams))
    })
    it('gas zeroForOne=false', async () => {
      mineNextBlock(expiryTime)
      blocktime = (await ethers.provider.getBlock('latest')).timestamp
      const newExpiryTime = findExpiryTime(blocktime, 3, EXPIRATION_INTERVAL)
      await twamm.executeTWAMMOrders(poolParams)
      await twamm.submitLongTermOrder({
        zeroForOne: false,
        owner: wallet.address,
        amountIn: fullSellAmount,
        expiration: newExpiryTime,
      })
      mineNextBlock(newExpiryTime)
      await snapshotGasCost(twamm.executeTWAMMOrders(poolParams))
    })
  })

  describe('end-to-end simulation', async () => {
    it('distributes correct rewards on equal trading pools at a price of 1', async () => {
      const sqrtPriceX96 = encodeSqrtPriceX96(1, 1)
      const liquidity = '1000000000000000000000000'
      const fee = '3000'
      const tickSpacing = 60
      const feeProtocol = 0

      const poolParams = { feeProtocol, sqrtPriceX96, liquidity, fee, tickSpacing }

      const poolKey = { token0: ZERO_ADDR, token1: ZERO_ADDR, tickSpacing: TICK_SPACING, fee: FEE, hooks: ZERO_ADDR }
      await twamm.initialize(poolKey)

      const latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
      const timestampInterval1 = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 1)
      const timestampInterval2 = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 3)
      const timestampInterval3 = nIntervalsFrom(latestTimestamp, EXPIRATION_INTERVAL, 4)

      const halfSellAmount = toWei('2.5')
      const fullSellAmount = toWei('5')
      const fullSellRate = fullSellAmount.div(timestampInterval2 - timestampInterval1)

      const owner = wallet.address
      const expiration = timestampInterval2
      const orderKey1 = { owner, expiration, zeroForOne: true }
      const orderKey2 = { owner, expiration, zeroForOne: true }
      const orderKey3 = { owner, expiration, zeroForOne: false }

      expect((await twamm.getOrderPool(0)).sellRate).to.eq(0)
      expect((await twamm.getOrderPool(1)).sellRate).to.eq(0)

      await executeTwammAndThen(timestampInterval1, poolParams, async () => {
        await twamm.submitLongTermOrder({
          zeroForOne: true,
          owner,
          amountIn: halfSellAmount,
          expiration: timestampInterval2,
        })
        await twamm.submitLongTermOrder({
          zeroForOne: true,
          owner: other.address,
          amountIn: halfSellAmount,
          expiration: timestampInterval2,
        })
        await twamm.submitLongTermOrder({
          zeroForOne: false,
          owner,
          amountIn: fullSellAmount,
          expiration: timestampInterval2,
        })
      })

      expect((await twamm.getOrderPool(0)).sellRate).to.eq(fullSellRate)
      expect((await twamm.getOrderPool(1)).sellRate).to.eq(fullSellRate)
      expect((await twamm.getOrderPool(0)).earningsFactor).to.eq('0')
      expect((await twamm.getOrderPool(1)).earningsFactor).to.eq('0')

      await ethers.provider.send('evm_setNextBlockTimestamp', [timestampInterval2])
      await twamm.executeTWAMMOrders(poolParams)

      expect((await twamm.callStatic.getOrderPool(0)).sellRate).to.eq('0')
      expect((await twamm.callStatic.getOrderPool(1)).sellRate).to.eq('0')
      expect((await twamm.callStatic.getOrderPool(0)).earningsFactor).to.eq('1584563250285286751870879006720000')
      expect((await twamm.callStatic.getOrderPool(1)).earningsFactor).to.eq('1584563250285286751870879006720000')

      await ethers.provider.send('evm_setNextBlockTimestamp', [timestampInterval3])
      await twamm.executeTWAMMOrders(poolParams)

      expect((await twamm.getOrderPool(0)).sellRate).to.eq('0')
      expect((await twamm.getOrderPool(1)).sellRate).to.eq('0')
      expect((await twamm.getOrderPool(0)).earningsFactor).to.eq('1584563250285286751870879006720000')
      expect((await twamm.getOrderPool(1)).earningsFactor).to.eq('1584563250285286751870879006720000')

      expect((await twamm.getOrder(orderKey1)).sellRate).to.eq(halfSellAmount.div(20_000))
      expect((await twamm.getOrder(orderKey2)).sellRate).to.eq(halfSellAmount.div(20_000))
      expect((await twamm.getOrder(orderKey3)).sellRate).to.eq(fullSellAmount.div(20_000))

      expect((await twamm.callStatic.claimEarnings(orderKey1)).earningsAmount).to.eq(halfSellAmount)
      expect((await twamm.callStatic.claimEarnings(orderKey2)).earningsAmount).to.eq(halfSellAmount)
      expect((await twamm.callStatic.claimEarnings(orderKey3)).earningsAmount).to.eq(fullSellAmount)
    })
  })
})
