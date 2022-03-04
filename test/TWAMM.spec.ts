import { BigNumber, BigNumberish, Wallet } from 'ethers'
import { ethers, waffle } from 'hardhat'
import { TWAMMTest } from '../typechain/TWAMMTest'
import checkObservationEquals from './shared/checkObservationEquals'
import { expect } from './shared/expect'
import snapshotGasCost from './shared/snapshotGasCost'
import { MaxUint128 } from './shared/utilities'

describe.only('TWAMM', () => {
  let wallet: Wallet, other: Wallet

  let loadFixture: ReturnType<typeof waffle.createFixtureLoader>
  before('create fixture loader', async () => {
    ;[wallet, other] = await (ethers as any).getSigners()
    loadFixture = waffle.createFixtureLoader([wallet, other])
  })

  const twammFixture = async () => {
    const twammTestFactory = await ethers.getContractFactory('TWAMMTest')
    return (await twammTestFactory.deploy()) as TWAMMTest
  }

  describe('#submitLongTermOrder', () => {
    let twamm: TWAMMTest
    beforeEach('deploy test twamm', async () => {
      twamm = await loadFixture(twammFixture)
    })

    it('stores the new long term order', async () => {
      const nextId = await twamm.getNextId()

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

      const latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
      const sellingRate = amountIn.div(expiration - latestTimestamp)

      const newOrder = await twamm.getOrder(nextId)

      expect(newOrder.zeroForOne).to.equal(zeroForOne)
      expect(newOrder.owner).to.equal(owner)
      expect(newOrder.sellingRate).to.equal(sellingRate)
      expect(newOrder.expiration).to.equal(expiration)
    })

    it('increases the sellingRate of the corresponding OrderPool', async () => {
      const nextId = await twamm.getNextId()

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

      const latestTimestamp = (await ethers.provider.getBlock('latest')).timestamp
      const sellingRate = amountIn.div(expiration - latestTimestamp)

      const orderPool = await twamm.getOrderPool(0)
      expect(orderPool.sellingRate).to.equal(sellingRate)
    })
  })

  describe('#cancelLongTermOrder', () => {
    let twamm: TWAMMTest
    let orderId: BigNumber

    beforeEach('deploy test twamm', async () => {
      twamm = await loadFixture(twammFixture)
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

    it('deletes the long term order', async () => {
      // actually wondering if this should happen, tbd
      await twamm.cancelLongTermOrder(orderId)
    })

    it('decreases the sellingRate of the corresponding OrderPool', async () => {
      expect(parseInt((await twamm.getOrderPool(0)).sellingRate.toString())).to.be.greaterThan(0)
      await twamm.cancelLongTermOrder(orderId)
      expect((await twamm.getOrderPool(0)).sellingRate).to.equal(0)
    })
  })
})
