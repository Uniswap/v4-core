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
    let expiration: number

    beforeEach('deploy test twamm', async () => {
      zeroForOne = true
      owner = wallet.address
      amountIn = BigNumber.from(`1${'0'.repeat(18)}`)
      expiration = (await ethers.provider.getBlock('latest')).timestamp + 86400
    })

    it('stores the new long term order', async () => {
      const nextId = await twamm.getNextId()

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
      orderId = await twamm.getNextId()

      const zeroForOne = true
      const owner = wallet.address
      const amountIn = BigNumber.from(`1${'0'.repeat(18)}`)
      const expiration = (await ethers.provider.getBlock('latest')).timestamp + 86400

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

  describe('#calculateTWAMMExecutionUpdates', () => {
    describe('without any initialized ticks', () => {
      it('returns the correct parameters', async () => {
        const startTime = 0
        // TODO: a longer timestamp overflows
        // 43315
        const endTime = 20
        const sqrtPriceX96 = encodeSqrtPriceX96(1, 1)
        const feeProtocol = 0
        const liquidity = 50
        const orderPool0SellRate = 2
        const orderPool1SellRate = 4

        const vals = await twamm.callStatic.calculateTWAMMExecutionUpdates(
          startTime,
          endTime,
          {
            feeProtocol,
            sqrtPriceX96,
            liquidity,
          },
          {
            orderPool0SellRate,
            orderPool1SellRate,
          }
        )
      })
    })
  })

  describe.skip('#claimEarnings', () => {
    let orderId: BigNumber

    const mockTicks = {}
    const poolParams = { feeProtocol: 0, sqrtPriceX96: encodeSqrtPriceX96(1, 1), liquidity: 1000 }

    beforeEach('create new longTermOrder', async () => {
      orderId = await twamm.getNextId()

      const zeroForOne = {
        zeroForOne: true,
        owner: wallet.address,
        amountIn: BigNumber.from(`2${'0'.repeat(5)}`),
        // 24 hours
        expiration: (await ethers.provider.getBlock('latest')).timestamp + 86400,
      }

      const oneForZero = {
        zeroForOne: false,
        owner: wallet.address,
        amountIn: BigNumber.from(`4${'0'.repeat(5)}`),
        expiration: (await ethers.provider.getBlock('latest')).timestamp + 86400,
      }

      await twamm.initialize(10_000)
      // TODO: test swaps in one direction
      await twamm.submitLongTermOrder(zeroForOne)
      await twamm.submitLongTermOrder(oneForZero)
    })
    it('should give correct earnings amount and have no unclaimed earnings', async () => {
      const afterExpiration = (await ethers.provider.getBlock('latest')).timestamp + 86400
      const expiration = (await twamm.getOrder(orderId)).expiration.toNumber()
      expect(afterExpiration).to.be.greaterThan(expiration)

      advanceTime(afterExpiration)

      const tx = await twamm.claimEarnings(orderId, poolParams, mockTicks)
      const tr = await tx.wait()

      // console.log(tr.events![0].args)

      const earningsAmount = tr.events![0].args![0]
      const unclaimed = tr.events![0].args![1]!

      // TODO: calculate expected earningsAmount
      // expect(earningsAmount).to.be.greaterThan(0)
      // expect(unclaimedEarnings).to.eq(0)
    })

    it('should give correct earningsAmount and have some unclaimed earnings', async () => {
      const beforeExpiration = (await ethers.provider.getBlock('latest')).timestamp + 43200
      advanceTime(beforeExpiration)
      const tx = await twamm.claimEarnings(orderId, poolParams, mockTicks)
      const tr = await tx.wait()

      const earningsAmount = tr.events![0].args![0]
      const unclaimed = tr.events![0].args![1]

      // TODO: calculate expected earningsAmount
      // expect(earningsAmount).to.greaterThan(0)
      // expect(unclaimed).to.be.greaterThan(0)
    })
  })
})
