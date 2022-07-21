import snapshotGasCost from '@uniswap/snapshot-gas-cost'
import { ethers } from 'hardhat'
import { BigNumber } from 'ethers'
import { TickTest } from '../typechain/TickTest'
import { MAX_TICK_SPACING } from './shared/constants'
import { expect } from './shared/expect'
import { FeeAmount, getMaxTick, getMinTick, TICK_SPACINGS } from './shared/utilities'

const MaxUint128 = BigNumber.from(2).pow(128).sub(1)

const { constants } = ethers

describe('Tick', () => {
  let tickTest: TickTest

  beforeEach('deploy TickTest', async () => {
    const tickTestFactory = await ethers.getContractFactory('TickTest')
    tickTest = (await tickTestFactory.deploy()) as TickTest
  })

  describe('#tickSpacingToMaxLiquidityPerTick', () => {
    function checkCantOverflow(tickSpacing: number, maxLiquidityPerTick: BigNumber) {
      expect(
        maxLiquidityPerTick.mul((getMaxTick(tickSpacing) - getMinTick(tickSpacing)) / tickSpacing + 1),
        'max liquidity if all ticks are full'
      ).to.be.lte(MaxUint128)
    }

    it('returns the correct value for low fee tick spacing', async () => {
      const maxLiquidityPerTick = await tickTest.tickSpacingToMaxLiquidityPerTick(TICK_SPACINGS[FeeAmount.LOW])
      expect(maxLiquidityPerTick).to.eq('1917565579412846627735051215301243')
      checkCantOverflow(TICK_SPACINGS[FeeAmount.LOW], maxLiquidityPerTick)
    })
    it('returns the correct value for medium fee tick spacing', async () => {
      const maxLiquidityPerTick = await tickTest.tickSpacingToMaxLiquidityPerTick(TICK_SPACINGS[FeeAmount.MEDIUM])
      expect(maxLiquidityPerTick).to.eq('11505069308564788430434325881101413') // 113.1 bits
      checkCantOverflow(TICK_SPACINGS[FeeAmount.MEDIUM], maxLiquidityPerTick)
    })
    it('returns the correct value for high fee tick spacing', async () => {
      const maxLiquidityPerTick = await tickTest.tickSpacingToMaxLiquidityPerTick(TICK_SPACINGS[FeeAmount.HIGH])
      expect(maxLiquidityPerTick).to.eq('38347205785278154309959589375342946') // 114.7 bits
      checkCantOverflow(TICK_SPACINGS[FeeAmount.HIGH], maxLiquidityPerTick)
    })

    it('returns the correct value for 1', async () => {
      const maxLiquidityPerTick = await tickTest.tickSpacingToMaxLiquidityPerTick(1)
      expect(maxLiquidityPerTick).to.eq('191757530477355301479181766273477') // 126 bits
      checkCantOverflow(1, maxLiquidityPerTick)
    })
    it('returns the correct value for entire range', async () => {
      const maxLiquidityPerTick = await tickTest.tickSpacingToMaxLiquidityPerTick(887272)
      expect(maxLiquidityPerTick).to.eq(MaxUint128.div(3)) // 126 bits
      checkCantOverflow(887272, maxLiquidityPerTick)
    })

    it('returns the correct value for 2302', async () => {
      const maxLiquidityPerTick = await tickTest.tickSpacingToMaxLiquidityPerTick(2302)
      expect(maxLiquidityPerTick).to.eq('440854192570431170114173285871668350') // 118 bits
      checkCantOverflow(2302, maxLiquidityPerTick)
    })

    it('gas cost min tick spacing', async () => {
      await snapshotGasCost(tickTest.getGasCostOfTickSpacingToMaxLiquidityPerTick(1))
    })

    it('gas cost 60 tick spacing', async () => {
      await snapshotGasCost(tickTest.getGasCostOfTickSpacingToMaxLiquidityPerTick(60))
    })

    it('gas cost max tick spacing', async () => {
      await snapshotGasCost(tickTest.getGasCostOfTickSpacingToMaxLiquidityPerTick(MAX_TICK_SPACING))
    })
  })

  describe('#getFeeGrowthInside', () => {
    it('returns all for two uninitialized ticks if tick is inside', async () => {
      const { feeGrowthInside0X128, feeGrowthInside1X128 } = await tickTest.callStatic.getFeeGrowthInside(
        -2,
        2,
        0,
        15,
        15
      )
      expect(feeGrowthInside0X128).to.eq(15)
      expect(feeGrowthInside1X128).to.eq(15)
    })
    it('returns 0 for two uninitialized ticks if tick is above', async () => {
      const { feeGrowthInside0X128, feeGrowthInside1X128 } = await tickTest.callStatic.getFeeGrowthInside(
        -2,
        2,
        4,
        15,
        15
      )
      expect(feeGrowthInside0X128).to.eq(0)
      expect(feeGrowthInside1X128).to.eq(0)
    })
    it('returns 0 for two uninitialized ticks if tick is below', async () => {
      const { feeGrowthInside0X128, feeGrowthInside1X128 } = await tickTest.callStatic.getFeeGrowthInside(
        -2,
        2,
        -4,
        15,
        15
      )
      expect(feeGrowthInside0X128).to.eq(0)
      expect(feeGrowthInside1X128).to.eq(0)
    })

    it('subtracts upper tick if below', async () => {
      await tickTest.setTick(2, {
        feeGrowthOutside0X128: 2,
        feeGrowthOutside1X128: 3,
        liquidityGross: 0,
        liquidityNet: 0,
      })
      const { feeGrowthInside0X128, feeGrowthInside1X128 } = await tickTest.callStatic.getFeeGrowthInside(
        -2,
        2,
        0,
        15,
        15
      )
      expect(feeGrowthInside0X128).to.eq(13)
      expect(feeGrowthInside1X128).to.eq(12)
    })

    it('subtracts lower tick if above', async () => {
      await tickTest.setTick(-2, {
        feeGrowthOutside0X128: 2,
        feeGrowthOutside1X128: 3,
        liquidityGross: 0,
        liquidityNet: 0,
      })
      const { feeGrowthInside0X128, feeGrowthInside1X128 } = await tickTest.callStatic.getFeeGrowthInside(
        -2,
        2,
        0,
        15,
        15
      )
      expect(feeGrowthInside0X128).to.eq(13)
      expect(feeGrowthInside1X128).to.eq(12)
    })

    it('subtracts upper and lower tick if inside', async () => {
      await tickTest.setTick(-2, {
        feeGrowthOutside0X128: 2,
        feeGrowthOutside1X128: 3,
        liquidityGross: 0,
        liquidityNet: 0,
      })
      await tickTest.setTick(2, {
        feeGrowthOutside0X128: 4,
        feeGrowthOutside1X128: 1,
        liquidityGross: 0,
        liquidityNet: 0,
      })
      const { feeGrowthInside0X128, feeGrowthInside1X128 } = await tickTest.callStatic.getFeeGrowthInside(
        -2,
        2,
        0,
        15,
        15
      )
      expect(feeGrowthInside0X128).to.eq(9)
      expect(feeGrowthInside1X128).to.eq(11)
    })

    it('works correctly with overflow on inside tick', async () => {
      await tickTest.setTick(-2, {
        feeGrowthOutside0X128: constants.MaxUint256.sub(3),
        feeGrowthOutside1X128: constants.MaxUint256.sub(2),
        liquidityGross: 0,
        liquidityNet: 0,
      })
      await tickTest.setTick(2, {
        feeGrowthOutside0X128: 3,
        feeGrowthOutside1X128: 5,
        liquidityGross: 0,
        liquidityNet: 0,
      })
      const { feeGrowthInside0X128, feeGrowthInside1X128 } = await tickTest.callStatic.getFeeGrowthInside(
        -2,
        2,
        0,
        15,
        15
      )
      expect(feeGrowthInside0X128).to.eq(16)
      expect(feeGrowthInside1X128).to.eq(13)
    })
  })

  describe('#update', async () => {
    it('flips from zero to nonzero', async () => {
      const { flipped, liquidityGrossAfter } = await tickTest.callStatic.update(0, 0, 1, 0, 0, false)
      expect(flipped).to.eq(true)
      expect(liquidityGrossAfter).to.eq(1)
    })
    it('does not flip from nonzero to greater nonzero', async () => {
      await tickTest.update(0, 0, 1, 0, 0, false)
      const { flipped, liquidityGrossAfter } = await tickTest.callStatic.update(0, 0, 1, 0, 0, false)
      expect(flipped).to.eq(false)
      expect(liquidityGrossAfter).to.eq(2)
    })
    it('flips from nonzero to zero', async () => {
      await tickTest.update(0, 0, 1, 0, 0, false)
      const { flipped, liquidityGrossAfter } = await tickTest.callStatic.update(0, 0, -1, 0, 0, false)
      expect(flipped).to.eq(true)
      expect(liquidityGrossAfter).to.eq(0)
    })
    it('does not flip from nonzero to lesser nonzero', async () => {
      await tickTest.update(0, 0, 2, 0, 0, false)
      const { flipped, liquidityGrossAfter } = await tickTest.callStatic.update(0, 0, -1, 0, 0, false)
      expect(flipped).to.eq(false)
      expect(liquidityGrossAfter).to.eq(1)
    })
    it('nets the liquidity based on upper flag', async () => {
      await tickTest.update(0, 0, 2, 0, 0, false)
      await tickTest.update(0, 0, 1, 0, 0, true)
      await tickTest.update(0, 0, 3, 0, 0, true)
      await tickTest.update(0, 0, 1, 0, 0, false)
      const { liquidityGross, liquidityNet } = await tickTest.ticks(0)
      expect(liquidityGross).to.eq(2 + 1 + 3 + 1)
      expect(liquidityNet).to.eq(2 - 1 - 3 + 1)
    })
    it('reverts on overflow liquidity gross', async () => {
      await tickTest.update(0, 0, MaxUint128.div(2).sub(1), 0, 0, false)
      await expect(tickTest.update(0, 0, MaxUint128.div(2).sub(1), 0, 0, false)).to.be.reverted
    })
    it('assumes all growth happens below ticks lte current tick', async () => {
      await tickTest.update(1, 1, 1, 1, 2, false)
      const { feeGrowthOutside0X128, feeGrowthOutside1X128 } = await tickTest.ticks(1)
      expect(feeGrowthOutside0X128).to.eq(1)
      expect(feeGrowthOutside1X128).to.eq(2)
    })
    it('does not set any growth fields if tick is already initialized', async () => {
      await tickTest.update(1, 1, 1, 1, 2, false)
      await tickTest.update(1, 1, 1, 6, 7, false)
      const { feeGrowthOutside0X128, feeGrowthOutside1X128 } = await tickTest.ticks(1)
      expect(feeGrowthOutside0X128).to.eq(1)
      expect(feeGrowthOutside1X128).to.eq(2)
    })
    it('does not set any growth fields for ticks gt current tick', async () => {
      await tickTest.update(2, 1, 1, 1, 2, false)
      const { feeGrowthOutside0X128, feeGrowthOutside1X128 } = await tickTest.ticks(2)
      expect(feeGrowthOutside0X128).to.eq(0)
      expect(feeGrowthOutside1X128).to.eq(0)
    })

    describe('liquidity parsing', async () => {
      it('parses max uint128 stored liquidityGross before update', async () => {
        await tickTest.setTick(2, {
          feeGrowthOutside0X128: 0,
          feeGrowthOutside1X128: 0,
          liquidityGross: MaxUint128,
          liquidityNet: 0,
        })

        await tickTest.update(2, 1, -1, 1, 2, false)
        const { liquidityGross, liquidityNet } = await tickTest.ticks(2)
        expect(liquidityGross).to.eq(MaxUint128.sub(1))
        expect(liquidityNet).to.eq(-1)
      })
      it('parses max uint128 stored liquidityGross after update', async () => {
        await tickTest.setTick(2, {
          feeGrowthOutside0X128: 0,
          feeGrowthOutside1X128: 0,
          liquidityGross: MaxUint128.div(2).add(1),
          liquidityNet: 0,
        })

        await tickTest.update(2, 1, MaxUint128.div(2), 1, 2, false)
        const { liquidityGross, liquidityNet } = await tickTest.ticks(2)
        expect(liquidityGross).to.eq(MaxUint128)
        expect(liquidityNet).to.eq(MaxUint128.div(2))
      })
      it('parses max int128 stored liquidityNet before update', async () => {
        await tickTest.setTick(2, {
          feeGrowthOutside0X128: 0,
          feeGrowthOutside1X128: 0,
          liquidityGross: 1,
          liquidityNet: MaxUint128.div(2),
        })

        await tickTest.update(2, 1, -1, 1, 2, false)
        const { liquidityGross, liquidityNet } = await tickTest.ticks(2)
        expect(liquidityGross).to.eq(0)
        expect(liquidityNet).to.eq(MaxUint128.div(2).sub(1))
      })
      it('parses max int128 stored liquidityNet after update', async () => {
        await tickTest.setTick(2, {
          feeGrowthOutside0X128: 0,
          feeGrowthOutside1X128: 0,
          liquidityGross: 0,
          liquidityNet: MaxUint128.div(2).sub(1),
        })

        await tickTest.update(2, 1, 1, 1, 2, false)
        const { liquidityGross, liquidityNet } = await tickTest.ticks(2)
        expect(liquidityGross).to.eq(1)
        expect(liquidityNet).to.eq(MaxUint128.div(2))
      })
    })
  })

  // this is skipped because the presence of the method causes slither to fail
  describe('#clear', async () => {
    it('deletes all the data in the tick', async () => {
      await tickTest.setTick(2, {
        feeGrowthOutside0X128: 1,
        feeGrowthOutside1X128: 2,
        liquidityGross: 3,
        liquidityNet: 4,
      })
      await tickTest.clear(2)
      const { feeGrowthOutside0X128, feeGrowthOutside1X128, liquidityGross, liquidityNet } = await tickTest.ticks(2)
      expect(feeGrowthOutside0X128).to.eq(0)
      expect(feeGrowthOutside1X128).to.eq(0)
      expect(liquidityGross).to.eq(0)
      expect(liquidityNet).to.eq(0)
    })
  })

  describe('#cross', () => {
    it('flips the growth variables', async () => {
      await tickTest.setTick(2, {
        feeGrowthOutside0X128: 1,
        feeGrowthOutside1X128: 2,
        liquidityGross: 3,
        liquidityNet: 4,
      })
      await tickTest.cross(2, 7, 9)
      const { feeGrowthOutside0X128, feeGrowthOutside1X128 } = await tickTest.ticks(2)
      expect(feeGrowthOutside0X128).to.eq(6)
      expect(feeGrowthOutside1X128).to.eq(7)
    })
    it('two flips are no op', async () => {
      await tickTest.setTick(2, {
        feeGrowthOutside0X128: 1,
        feeGrowthOutside1X128: 2,
        liquidityGross: 3,
        liquidityNet: 4,
      })
      await tickTest.cross(2, 7, 9)
      await tickTest.cross(2, 7, 9)
      const { feeGrowthOutside0X128, feeGrowthOutside1X128 } = await tickTest.ticks(2)
      expect(feeGrowthOutside0X128).to.eq(1)
      expect(feeGrowthOutside1X128).to.eq(2)
    })
  })
})
