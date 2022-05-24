import { expect } from './shared/expect'
import { BitMathVyper } from '../typechain/BitMathVyper'
import { ethers, waffle } from 'hardhat'
import snapshotGasCost from '@uniswap/snapshot-gas-cost'

const { BigNumber } = ethers

describe('BitMathVyper', () => {
  let bitMath: BitMathVyper
  const fixture = async () => {
    const factory = await ethers.getContractFactory('BitMathVyper')
    return (await factory.deploy()) as BitMathVyper
  }
  beforeEach('deploy BitMathVyper', async () => {
    bitMath = await waffle.loadFixture(fixture)
  })

  describe('#mostSignificantBit', () => {
    it('0', async () => {
      await expect(bitMath.mostSignificantBitExternal(0)).to.be.reverted
    })
    it('1', async () => {
      expect(await bitMath.mostSignificantBitExternal(1)).to.eq(0)
    })
    it('2', async () => {
      expect(await bitMath.mostSignificantBitExternal(2)).to.eq(1)
    })
    it('all powers of 2', async () => {
      const results = await Promise.all(
        [...Array(255)].map((_, i) => bitMath.mostSignificantBitExternal(BigNumber.from(2).pow(i)))
      )
      expect(results).to.deep.eq([...Array(255)].map((_, i) => i))
    })
    it('uint256(-1)', async () => {
      expect(await bitMath.mostSignificantBitExternal(BigNumber.from(2).pow(256).sub(1))).to.eq(255)
    })

    it('gas cost of smaller number', async () => {
      await snapshotGasCost(bitMath.getGasCostOfMostSignificantBit(BigNumber.from(3568)))
    })
    it('gas cost of max uint128', async () => {
      await snapshotGasCost(bitMath.getGasCostOfMostSignificantBit(BigNumber.from(2).pow(128).sub(1)))
    })
    it('gas cost of max uint256', async () => {
      await snapshotGasCost(bitMath.getGasCostOfMostSignificantBit(BigNumber.from(2).pow(256).sub(1)))
    })
  })
})
