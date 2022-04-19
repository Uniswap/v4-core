import { BigNumber, BigNumberish, Wallet } from 'ethers'
import { ethers, waffle } from 'hardhat'
import { TWAMMTest } from '../typechain/TWAMMTest'
import checkObservationEquals from './shared/checkObservationEquals'
import { expect } from './shared/expect'
import snapshotGasCost from '@uniswap/snapshot-gas-cost'
import { encodeSqrtPriceX96, MaxUint128 } from './shared/utilities'

async function advanceTime(time: number) {
  await ethers.provider.send('evm_mine', [time])
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

  beforeEach(async () => {
    twamm = await loadFixture(twammFixture)
  })

  const twammFixture = async () => {
    const twammTestFactory = await ethers.getContractFactory('TWAMMTest')
    return (await twammTestFactory.deploy()) as TWAMMTest
  }

  describe('initialize', () => {
    it('sets the initial state of the twamm', async () => {
      let { expirationInterval, lastVirtualOrderTimestamp } = await twamm.getState()
      expect(expirationInterval).to.equal(0)
      expect(lastVirtualOrderTimestamp).to.equal(0)

      await twamm.initialize(10_000)
      ;({ expirationInterval, lastVirtualOrderTimestamp } = await twamm.getState())
      expect(expirationInterval).to.equal(10_000)
      expect(lastVirtualOrderTimestamp).to.equal((await ethers.provider.getBlock('latest')).timestamp)
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
      ;(amountIn = toWei('1')), await twamm.initialize(10_000)
      const blocktime = (await ethers.provider.getBlock('latest')).timestamp
      nonIntervalExpiration = blocktime
      prevTimeExpiration = findExpiryTime(blocktime, -1, 10000)
      // gets the valid expiry time that is 3 intervals out
      expiration = findExpiryTime(blocktime, 3, 10000)
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

  describe('#cancelLongTermOrder', () => {
    let orderKey: OrderKey
    let interval: number
    let timestampInterval0: number

    beforeEach('deploy test twamm', async () => {
      twamm.initialize(10_000)

      const owner = wallet.address
      interval = 10_000
      const blocktime = (await ethers.provider.getBlock('latest')).timestamp
      timestampInterval0 = findExpiryTime(blocktime, 4, interval)
      const timestampInterval1 = findExpiryTime(blocktime, 5, interval)
      const timestampInterval2 = findExpiryTime(blocktime, 6, interval)

      orderKey = { owner, expiration: timestampInterval0, zeroForOne: true }
      await twamm.submitLongTermOrder({
        zeroForOne: true,
        owner,
        amountIn: toWei('3'),
        expiration: timestampInterval0,
      })

      // set two more expiry's so its never 0, logic isn't there yet
      await twamm.submitLongTermOrder({
        zeroForOne: false,
        owner,
        amountIn: toWei('2'),
        expiration: timestampInterval1,
      })

      await twamm.submitLongTermOrder({
        zeroForOne: true,
        owner,
        amountIn: toWei('2'),
        expiration: timestampInterval2,
      })
    })

    it('changes the sell rate of the order to 0', async () => {
      expect(parseInt((await twamm.getOrder(orderKey)).sellRate.toString())).to.be.greaterThan(0)
      await twamm.cancelLongTermOrder(orderKey)
      expect(parseInt((await twamm.getOrder(orderKey)).sellRate.toString())).to.be.eq(0)
    })

    it('claims some of the order, then cancels successfully', async () => {
      const poolParams = {
        feeProtocol: 0,
        sqrtPriceX96: encodeSqrtPriceX96(1, 1),
        fee: '3000',
        liquidity: '14496800315719602540',
        tickSpacing: 60,
      }
      advanceTime(timestampInterval0 - interval)

      await twamm.executeTWAMMOrders(poolParams)
      const result = await twamm.callStatic.claimEarnings(orderKey)
      const earningsAmount: BigNumber = result.earningsAmount
      const unclaimed: BigNumber = result.unclaimedEarnings
      // TODO: calculate expected earnings
      expect(parseInt(earningsAmount.toString())).to.be.greaterThan(0)
      expect(parseInt(unclaimed.toString())).to.be.greaterThan(0)

      await twamm.cancelLongTermOrder(orderKey)
      expect(parseInt((await twamm.getOrder(orderKey)).sellRate.toString())).to.eq(0)
      expect(parseInt((await twamm.getOrder(orderKey)).unclaimedEarningsFactor.toString())).to.eq(0)
    })

    it('reverts if you cancel after the expiration', async () => {
      advanceTime(timestampInterval0 + 5)
      expect(twamm.cancelLongTermOrder(orderKey)).to.be.reverted
    })

    it('claims half the amount, refunds half the amount', async () => {
      const sqrtPriceX96 = encodeSqrtPriceX96(1, 1)
      const liquidity = '1000000000000000000000000'
      const fee = '3000'
      const tickSpacing = 60

      const error = 5
      const fullSellAmount = toWei('5')
      const halfSellAmount = fullSellAmount.div(2)
      const halfSellAmountUnderError = halfSellAmount.sub(halfSellAmount.div(error))
      const halfSellAmountOverError = halfSellAmount.add(halfSellAmount.div(error))

      const poolParams = { sqrtPriceX96, liquidity, fee, tickSpacing }

      // set up timestamps
      const latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
      const submissionTimestamp = findExpiryTime(latestTimestamp, 1, interval) // start
      const midPointTimestamp = findExpiryTime(latestTimestamp, 2, interval) // midpoint
      const expiration = findExpiryTime(latestTimestamp, 3, interval) // expire

      // submit the order on an expiry interval for easier calculations
      await ethers.provider.send('evm_mine', [submissionTimestamp])

      await twamm.executeTWAMMOrders(poolParams)

      const orderToCancel = { owner: wallet.address, expiration, zeroForOne: true }
      await twamm.submitLongTermOrder({
        zeroForOne: true,
        owner: wallet.address,
        amountIn: fullSellAmount,
        expiration,
      })

      await twamm.submitLongTermOrder({
        zeroForOne: true,
        owner: other.address,
        amountIn: halfSellAmount,
        expiration,
      })

      await ethers.provider.send('evm_mine', [midPointTimestamp])

      // update state and cancel the order at the midpoint
      await twamm.executeTWAMMOrders(poolParams)
      const results = await twamm.callStatic.cancelLongTermOrder(orderToCancel)

      expect(parseInt(results.amountOut0.toString())).to.be.greaterThanOrEqual(
        parseInt(halfSellAmountUnderError.toString())
      )
      expect(parseInt(results.amountOut0.toString())).to.be.lessThanOrEqual(
        parseInt(halfSellAmountOverError.toString())
      )
      expect(parseInt(results.amountOut1.toString())).to.be.greaterThanOrEqual(
        parseInt(halfSellAmountUnderError.toString())
      )
      expect(parseInt(results.amountOut1.toString())).to.be.lessThanOrEqual(
        parseInt(halfSellAmountOverError.toString())
      )
    })

    it('gas', async () => {
      await snapshotGasCost(twamm.cancelLongTermOrder(orderKey))
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

      await twamm.initialize(10_000)

      latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
      timestampInterval1 = nIntervalsFrom(latestTimestamp, 10_000, 1)
      timestampInterval2 = nIntervalsFrom(latestTimestamp, 10_000, 2)
      timestampInterval3 = nIntervalsFrom(latestTimestamp, 10_000, 3)
      timestampInterval4 = nIntervalsFrom(latestTimestamp, 10_000, 4)

      await ethers.provider.send('evm_setAutomine', [false])

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
      await ethers.provider.send('evm_setAutomine', [true])
      await ethers.provider.send('evm_mine', [timestampInterval1])
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

      await twamm.executeTWAMMOrders({ sqrtPriceX96, liquidity, fee, tickSpacing })

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
      await snapshotGasCost(twamm.executeTWAMMOrders({ sqrtPriceX96, liquidity, fee, tickSpacing }))
    })
  })

  describe('#claimEarnings', () => {
    let orderKey: OrderKey
    const mockTicks = {}
    const poolParams = {
      feeProtocol: 0,
      sqrtPriceX96: encodeSqrtPriceX96(1, 1),
      fee: '3000',
      tickSpacing: '60',
      liquidity: '14496800315719602540',
    }
    let expiration: number
    let expiration2: number
    const interval = 10

    beforeEach('create new longTermOrders', async () => {
      await twamm.initialize(interval)

      const timestamp = (await ethers.provider.getBlock('latest')).timestamp
      expiration = findExpiryTime(timestamp, 2, interval)
      expiration2 = findExpiryTime(timestamp, 3, interval)

      orderKey = { owner: wallet.address, expiration, zeroForOne: true }

      const zeroForOne = {
        zeroForOne: true,
        owner: wallet.address,
        amountIn: toWei('2'),
        expiration: expiration,
      }

      const zeroForOne2 = {
        zeroForOne: true,
        owner: wallet.address,
        amountIn: toWei('2'),
        expiration: expiration2,
      }

      const oneForZero = {
        zeroForOne: false,
        owner: wallet.address,
        amountIn: toWei('4'),
        expiration: expiration2,
      }
      // TODO: Test swaps in one direction
      await twamm.submitLongTermOrder(zeroForOne)
      await twamm.submitLongTermOrder(oneForZero)
      await twamm.submitLongTermOrder(zeroForOne2)
    })

    it('should give correct earnings amount and have no unclaimed earnings', async () => {
      const expiration = (await twamm.getOrder(orderKey)).expiration.toNumber()
      const afterExpiration = expiration + interval / 2
      expect(afterExpiration).to.be.greaterThan(expiration)

      advanceTime(afterExpiration)

      await twamm.executeTWAMMOrders(poolParams)
      const result = await twamm.callStatic.claimEarnings(orderKey)

      const earningsAmount: BigNumber = result.earningsAmount
      const unclaimed: BigNumber = result.unclaimedEarnings

      // TODO: calculate expected earningsAmount
      expect(parseInt(earningsAmount.toString())).to.be.greaterThan(0)
      expect(parseInt(unclaimed.toString())).to.eq(0)
    })

    it('should give correct earningsAmount and have some unclaimed earnings', async () => {
      const expiration = (await twamm.getOrder(orderKey)).expiration.toNumber()
      const beforeExpiration = expiration - interval / 2

      advanceTime(beforeExpiration)

      await twamm.executeTWAMMOrders(poolParams)
      const result = await twamm.callStatic.claimEarnings(orderKey)

      const earningsAmount: BigNumber = result.earningsAmount
      const unclaimed: BigNumber = result.unclaimedEarnings

      // TODO: calculate expected earningsAmount
      expect(parseInt(earningsAmount.toString())).to.be.greaterThan(0)
      expect(parseInt(unclaimed.toString())).to.be.greaterThan(0)
    })
    // TODO: test an order that expires after only 1 interval and claim in between

    it('gas', async () => {
      const expiration = (await twamm.getOrder(orderKey)).expiration.toNumber()
      const afterExpiration = expiration + interval / 2

      advanceTime(afterExpiration)

      await snapshotGasCost(twamm.claimEarnings(orderKey))
    })
  })

  describe.only('#claimEarnings single pool', () => {
    let orderId: BigNumber
    const mockTicks = {}
    const poolParams = {
      feeProtocol: 0,
      sqrtPriceX96: encodeSqrtPriceX96(1, 1),
      fee: '3000',
      tickSpacing: '60',
      liquidity: '14496800315719602540',
    }
    let expiration: number
    let blocktime: number
    const interval = 10_000
    const zeroForOne = true

    beforeEach('submit one long term order', async () => {
      twamm.initialize(interval)
      //orderId = await twamm.getNextId()
      blocktime = (await ethers.provider.getBlock('latest')).timestamp
      console.log(blocktime)
      expiration = findExpiryTime(blocktime, 3, interval)
      await twamm.submitLongTermOrder({
        zeroForOne,
        owner: wallet.address,
        amountIn: toWei('2'),
        expiration: expiration,
      })
    })

    it.only('claims successfully for one pool', async () => {
      // advance time past 1 interval but not on the next interval
      // TODO: if you advance the time too far, you run out of gas
      // advanceTime(findExpiryTime(blocktime, 1, interval) + findExpiryTime(blocktime, 2, interval) / 2)

      advanceTime(findExpiryTime(blocktime, 1, interval) + 1000)
      blocktime = (await ethers.provider.getBlock('latest')).timestamp
      console.log(blocktime)

      const orderKey = { owner: wallet.address, expiration, zeroForOne: true }
      const results = await twamm.callStatic.claimEarnings(orderKey)

      const earningsAmount = results.earningsAmount

      // expect(earningsAmount).to.be.gt(0)
    })
  })

  describe('end-to-end simulation', async () => {
    it('distributes correct rewards on equal trading pools at a price of 1', async () => {
      const sqrtPriceX96 = encodeSqrtPriceX96(1, 1)
      const liquidity = '1000000000000000000000000'
      const fee = '3000'
      const tickSpacing = '60'

      const fullSellAmount = toWei('5')
      const halfSellAmount = toWei('2.5')

      const poolParams = { sqrtPriceX96, liquidity, fee, tickSpacing }

      await twamm.initialize(10_000)

      const latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
      const timestampInterval1 = nIntervalsFrom(latestTimestamp, 10_000, 1)
      const timestampInterval2 = nIntervalsFrom(latestTimestamp, 10_000, 3)
      const timestampInterval3 = nIntervalsFrom(latestTimestamp, 10_000, 4)

      const owner = wallet.address
      const expiration = timestampInterval2

      await ethers.provider.send('evm_setAutomine', [false])

      await twamm.executeTWAMMOrders(poolParams)

      const orderKey1 = { owner, expiration, zeroForOne: true }
      await twamm.submitLongTermOrder({
        zeroForOne: true,
        owner,
        amountIn: halfSellAmount,
        expiration: timestampInterval2,
      })

      const orderKey2 = { owner, expiration, zeroForOne: true }
      await twamm.submitLongTermOrder({
        zeroForOne: true,
        owner: other.address,
        amountIn: halfSellAmount,
        expiration: timestampInterval2,
      })

      const orderKey3 = { owner, expiration, zeroForOne: false }
      await twamm.submitLongTermOrder({
        zeroForOne: false,
        owner,
        amountIn: fullSellAmount,
        expiration: timestampInterval2,
      })

      expect((await twamm.getOrderPool(0)).sellRate).to.eq(0)
      expect((await twamm.getOrderPool(1)).sellRate).to.eq(0)

      await ethers.provider.send('evm_setAutomine', [true])
      await ethers.provider.send('evm_mine', [timestampInterval1])

      expect((await twamm.getOrderPool(0)).sellRate).to.eq('250000000000000')
      expect((await twamm.getOrderPool(1)).sellRate).to.eq('250000000000000')
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
