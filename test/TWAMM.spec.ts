import { BigNumber, BigNumberish, Wallet } from 'ethers'
import { ethers, waffle } from 'hardhat'
import { TWAMMTest } from '../typechain/TWAMMTest'
import checkObservationEquals from './shared/checkObservationEquals'
import { expect } from './shared/expect'
import snapshotGasCost from './shared/snapshotGasCost'
import { encodeSqrtPriceX96, MaxUint128 } from './shared/utilities'

describe.only('TWAMM', () => {
  let wallet: Wallet, other: Wallet
  let twamm: TWAMMTest

  let loadFixture: ReturnType<typeof waffle.createFixtureLoader>
  before('create fixture loader', async () => {
    ;[wallet, other] = await (ethers as any).getSigners()
    loadFixture = waffle.createFixtureLoader([wallet, other])
  })

  async function advanceTime(time: number) {
    await ethers.provider.send('evm_mine', [time])
  }

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
    let expiration: number

    beforeEach('deploy test twamm', async () => {
      zeroForOne = true
      owner = wallet.address
      amountIn = BigNumber.from(`1${'0'.repeat(18)}`)
      await twamm.initialize(10_000)
      const blocktime = (await ethers.provider.getBlock('latest')).timestamp
      nonIntervalExpiration = blocktime
      // gets the valid expiry time that is 3 intervals out
      expiration = findExpiryTime(blocktime, 3, 10000)
    })

    it('reverts because of bad expiry', async () => {
      const nextId = await twamm.getNextId()
      await expect(twamm.submitLongTermOrder({ zeroForOne, owner, amountIn, expiration: nonIntervalExpiration })).to.be
        .reverted
    })

    it('stores the new long term order', async () => {
      const nextId = await twamm.getNextId()
      // TODO: if the twamm is not initialized, should revert
      await twamm.submitLongTermOrder({
        zeroForOne,
        owner,
        amountIn,
        expiration,
      })

      const latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
      const sellRate = amountIn.div(expiration - latestTimestamp)

      const newOrder = await twamm.getOrder(nextId)

      expect(newOrder.sellTokenIndex).to.equal(0)
      expect(newOrder.owner).to.equal(owner)
      expect(newOrder.sellRate).to.equal(sellRate)
      expect(newOrder.expiration).to.equal(expiration)
    })

    it('increases the sellRate and sellRateEndingPerInterval of the corresponding OrderPool', async () => {
      const nextId = await twamm.getNextId()

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
    let orderId: BigNumber

    beforeEach('deploy test twamm', async () => {
      twamm.initialize(10_000)

      orderId = await twamm.getNextId()

      const zeroForOne = true
      const owner = wallet.address
      const amountIn = BigNumber.from(`1${'0'.repeat(18)}`)
      const expiration = findExpiryTime((await ethers.provider.getBlock('latest')).timestamp, 3, 10_000)

      await twamm.submitLongTermOrder({
        zeroForOne,
        owner,
        amountIn,
        expiration,
      })
    })

    it('changes the sell rate of the ordre to 0', async () => {
      expect(parseInt((await twamm.getOrder(orderId)).sellRate.toString())).to.be.greaterThan(0)
      await twamm.cancelLongTermOrder(orderId)
    })

    it('decreases the sellRate of the corresponding OrderPool', async () => {
      expect(parseInt((await twamm.getOrderPool(0)).sellRate.toString())).to.be.greaterThan(0)
      await twamm.cancelLongTermOrder(orderId)
      expect((await twamm.getOrderPool(0)).sellRate).to.equal(0)
    })

    it('gas', async () => {
      await snapshotGasCost(twamm.cancelLongTermOrder(orderId))
    })
  })

  describe('#executeTWAMMOrders', () => {
    let latestTimestamp: number
    let timestampInterval1: number
    let timestampInterval2: number
    let timestampInterval3: number
    let timestampInterval4: number

    function nIntervalsFrom(timestamp: number, interval: number, n: number): number {
      return timestamp + (interval - (timestamp % interval)) + interval * (n - 1)
    }

    beforeEach(async () => {
      latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
      timestampInterval1 = nIntervalsFrom(latestTimestamp, 10_000, 1)
      timestampInterval2 = nIntervalsFrom(latestTimestamp, 10_000, 2)
      timestampInterval3 = nIntervalsFrom(latestTimestamp, 10_000, 3)
      timestampInterval4 = nIntervalsFrom(latestTimestamp, 10_000, 4)

      await twamm.initialize(10_000)

      await twamm.submitLongTermOrder({
        zeroForOne: true,
        owner: wallet.address,
        amountIn: BigNumber.from(`1${'0'.repeat(18)}`),
        expiration: timestampInterval1,
      })

      await twamm.submitLongTermOrder({
        zeroForOne: false,
        owner: wallet.address,
        amountIn: BigNumber.from(`50${'0'.repeat(18)}`),
        expiration: timestampInterval3,
      })

      // set two more expiry's so its never 0, logic isn't there yet
      await twamm.submitLongTermOrder({
        zeroForOne: false,
        owner: wallet.address,
        amountIn: BigNumber.from(`2${'0'.repeat(18)}`),
        expiration: timestampInterval4,
      })

      await twamm.submitLongTermOrder({
        zeroForOne: true,
        owner: wallet.address,
        amountIn: BigNumber.from(`2${'0'.repeat(18)}`),
        expiration: timestampInterval4,
      })
    })

    it('updates all the necessarily intervals', async () => {
      const sqrtPriceX96 = encodeSqrtPriceX96(1, 1)
      const liquidity = '10000000000000000000'
      const fee = 3000
      await ethers.provider.send("evm_setNextBlockTimestamp", [timestampInterval3 + 5_000])

      expect(await twamm.getOrderPoolEarningsFactorAtInterval(0, timestampInterval1)).to.eq(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(1, timestampInterval1)).to.eq(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(0, timestampInterval2)).to.eq(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(1, timestampInterval2)).to.eq(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(0, timestampInterval3)).to.eq(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(1, timestampInterval3)).to.eq(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(0, timestampInterval4)).to.eq(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(1, timestampInterval4)).to.eq(0)

      await twamm.executeTWAMMOrders({ sqrtPriceX96, liquidity, fee })

      expect(await twamm.getOrderPoolEarningsFactorAtInterval(0, timestampInterval1)).to.be.gt(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(1, timestampInterval1)).to.be.gt(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(0, timestampInterval1)).to.be.gt(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(1, timestampInterval1)).to.be.gt(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(0, timestampInterval2)).to.eq(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(1, timestampInterval2)).to.eq(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(0, timestampInterval3)).to.be.gt(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(1, timestampInterval3)).to.be.gt(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(0, timestampInterval4)).to.eq(0)
      expect(await twamm.getOrderPoolEarningsFactorAtInterval(1, timestampInterval4)).to.eq(0)
    })

    it('updates all necessary intervals when block is mined exactly on an interval')

    it('gas', async () => {
      const sqrtPriceX96 = encodeSqrtPriceX96(1, 1)
      const liquidity = '10000000000000000000'
      const fee = 3000
      await ethers.provider.send("evm_setNextBlockTimestamp", [timestampInterval3 + 5_000])

      await snapshotGasCost(
        twamm.executeTWAMMOrders({ sqrtPriceX96, liquidity, fee })
      )
    })
  })

  describe('#calculateExecutionUpdates', () => {
    let secondsElapsed: BigNumberish
    let sqrtPriceX96: BigNumberish
    let liquidity: BigNumberish
    let fee: BigNumberish
    let sellRateCurrent0: BigNumberish
    let sellRateCurrent1: BigNumberish

    beforeEach(async () => {
       secondsElapsed = 3600
       sqrtPriceX96 = encodeSqrtPriceX96(1, 1)
       liquidity = '10000000000000000000'
       fee = '3000'
       sellRateCurrent0 = '10000000000000'
       sellRateCurrent1 = '5000'
    })

    describe('without any initialized ticks', () => {
      it('returns the correct parameters when sellRateCurrent0 is higher', async () => {
        const results = await twamm.callStatic.calculateExecutionUpdates(
          secondsElapsed,
          {
            sqrtPriceX96,
            liquidity,
            fee,
          },
          {
            sellRateCurrent0,
            sellRateCurrent1,
          }
        )
        expect(results.sqrtPriceX96).to.eq('78943964243131674870404435821')
        expect(results.earningsPool0).to.eq('284198271275273415665190322494405')
        expect(results.earningsPool1).to.eq('286249414193404035566722049114112') // TODO: this number is coming out incorrect
      })

      it('returns the correct parameters when sellRateCurrent1 is higher', async () => {
        sellRateCurrent0 = '5000'
        sellRateCurrent1 = '10000000000000'
        const results = await twamm.callStatic.calculateExecutionUpdates(
          secondsElapsed,
          {
            sqrtPriceX96,
            liquidity,
            fee,
          },
          {
            sellRateCurrent0,
            sellRateCurrent1,
          }
        )
        expect(results.sqrtPriceX96).to.eq('79513383899172564501784006539')
        expect(results.earningsPool0).to.eq('286249414193404035907969615921152') // TODO: this number is incorrect from desmos
        expect(results.earningsPool1).to.eq('284198271275273415665190322324995') // TODO: precision is off at the 5th decimal place
      })

      it('returns the correct parameters over longer time periods', async () => {
        secondsElapsed = 3600 * 100

        const results = await twamm.callStatic.calculateExecutionUpdates(
          secondsElapsed,
          {
            sqrtPriceX96,
            liquidity,
            fee,
          },
          {
            sellRateCurrent0,
            sellRateCurrent1,
          }
        )
        expect(results.sqrtPriceX96).to.eq('58256001859542945232537908987')
        expect(results.earningsPool0).to.eq('20972160668982461613573622115003872') // TODO: precision off at 5th decimal place
        expect(results.earningsPool1).to.eq('40022264742331847176083518403903488') // TODO: this number is incorrect in desmos, but close-ish
      })

      it('gas', async () => {
        await snapshotGasCost(
          twamm.calculateExecutionUpdates(
            secondsElapsed,
            {
              sqrtPriceX96,
              liquidity,
              fee,
            },
            {
              sellRateCurrent0,
              sellRateCurrent1,
            }
          )
        )
      })

      it('returns the correct parameters when TWAMM trades pushes the price to the max part of the curve')

      it('returns the correct parameters when TWAMM trades pushes the price to the min part of the curve')

      it('returns the correct parameters when orderPool1 has a 0 sell rate')

      it('returns the correct parameters when orderPool0 has a 0 sell rate')
    })
  })

  describe('#claimEarnings', () => {
    let orderId: BigNumber
    const mockTicks = {}
    const poolParams = {
      feeProtocol: 0,
      sqrtPriceX96: encodeSqrtPriceX96(1, 1),
      fee: '3000',
      liquidity: '14496800315719602540',
    }
    let expiration: number
    let expiration2: number
    const interval = 10

    beforeEach('create new longTermOrder', async () => {
      await twamm.initialize(interval)

      orderId = await twamm.getNextId()
      const timestamp = (await ethers.provider.getBlock('latest')).timestamp
      expiration = findExpiryTime(timestamp, 2, interval)
      expiration2 = findExpiryTime(timestamp, 3, interval)

      const zeroForOne = {
        zeroForOne: true,
        owner: wallet.address,
        amountIn: BigNumber.from(`2${'0'.repeat(5)}`),
        expiration: expiration,
      }

      const zeroForOne2 = {
        zeroForOne: true,
        owner: wallet.address,
        amountIn: BigNumber.from(`2${'0'.repeat(5)}`),
        expiration: expiration2,
      }

      const oneForZero = {
        zeroForOne: false,
        owner: wallet.address,
        amountIn: BigNumber.from(`4${'0'.repeat(5)}`),
        expiration: expiration2,
      }
      // TODO: Test swaps in one direction
      await twamm.submitLongTermOrder(zeroForOne)
      await twamm.submitLongTermOrder(oneForZero)
      await twamm.submitLongTermOrder(zeroForOne2)
    })

    it('should give correct earnings amount and have no unclaimed earnings', async () => {
      const expiration = (await twamm.getOrder(orderId)).expiration.toNumber()
      const afterExpiration = expiration + interval / 2
      expect(afterExpiration).to.be.greaterThan(expiration)

      advanceTime(afterExpiration)

      const result = await twamm.callStatic.claimEarnings(orderId, poolParams, mockTicks)

      const earningsAmount: BigNumber = result.earningsAmount
      const unclaimed: BigNumber = result.unclaimedEarnings

      // TODO: calculate expected earningsAmount
      expect(earningsAmount.toNumber()).to.be.greaterThan(0)
      expect(unclaimed.toNumber()).to.eq(0)
    })

    it('should give correct earningsAmount and have some unclaimed earnings', async () => {
      const expiration = (await twamm.getOrder(orderId)).expiration.toNumber()
      const beforeExpiration = expiration - interval / 2

      advanceTime(beforeExpiration)

      const result = await twamm.callStatic.claimEarnings(orderId, poolParams, mockTicks)

      const earningsAmount: BigNumber = result.earningsAmount
      const unclaimed: BigNumber = result.unclaimedEarnings

      // TODO: calculate expected earningsAmount
      expect(earningsAmount.toNumber()).to.be.greaterThan(0)
      expect(parseInt(unclaimed.toString())).to.be.greaterThan(0)
    })
    // TODO: test an order that expires after only 1 interval and claim in between

    it('gas', async () => {
      const expiration = (await twamm.getOrder(orderId)).expiration.toNumber()
      const afterExpiration = expiration + interval / 2

      advanceTime(afterExpiration)

      await snapshotGasCost(twamm.claimEarnings(orderId, poolParams, mockTicks))
    })
  })
})
