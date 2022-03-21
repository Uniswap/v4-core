import { expect } from './shared/expect'
import { HooksTest } from '../typechain/HooksTest'
import { ethers, waffle } from 'hardhat'
import snapshotGasCost from '@uniswap/snapshot-gas-cost'

const { BigNumber } = ethers

describe('Hooks', () => {
  let hooks: HooksTest
  const fixture = async () => {
    const factory = await ethers.getContractFactory('HooksTest')
    return (await factory.deploy()) as HooksTest
  }
  beforeEach('deploy HooksTest', async () => {
    hooks = await waffle.loadFixture(fixture)
  })

  describe('#validateHookAddress', () => {
    it('succeeds', async () => {
      expect(
        await hooks.isValidHookAddress('0x0000000000000000000000000000000000000000', {
          beforeModifyPosition: false,
          afterModifyPosition: false,
          beforeSwap: false,
          afterSwap: false,
        })
      ).to.be.true
    })

    it('succeeds for before swap only', async () => {
      expect(
        // 0x1000...
        await hooks.isValidHookAddress('0x8000000000000000000000000000000000000000', {
          beforeSwap: true,
          afterSwap: false,
          beforeModifyPosition: false,
          afterModifyPosition: false,
        })
      ).to.be.true
    })

    it('succeeds for after swap only', async () => {
      expect(
        // 0x0100...
        await hooks.isValidHookAddress('0x4000000000000000000000000000000000000000', {
          beforeSwap: false,
          afterSwap: true,
          beforeModifyPosition: false,
          afterModifyPosition: false,
        })
      ).to.be.true
    })

    it('succeeds for before and after swap only', async () => {
      expect(
        // 0x1100...
        await hooks.isValidHookAddress('0xC000000000000000000000000000000000000000', {
          beforeSwap: true,
          afterSwap: true,
          beforeModifyPosition: false,
          afterModifyPosition: false,
        })
      ).to.be.true
    })

    it('succeeds for before modify position only', async () => {
      expect(
        // 0x0010...
        await hooks.isValidHookAddress('0x2000000000000000000000000000000000000000', {
          beforeSwap: false,
          afterSwap: false,
          beforeModifyPosition: true,
          afterModifyPosition: false,
        })
      ).to.be.true
    })

    it('succeeds for after modify position only', async () => {
      expect(
        // 0x0001...
        await hooks.isValidHookAddress('0x1000000000000000000000000000000000000000', {
          beforeSwap: false,
          afterSwap: false,
          beforeModifyPosition: false,
          afterModifyPosition: true,
        })
      ).to.be.true
    })

    it('succeeds for before and after modify position only', async () => {
      expect(
        // 0x0011...
        await hooks.isValidHookAddress('0x3000000000000000000000000000000000000000', {
          beforeSwap: false,
          afterSwap: false,
          beforeModifyPosition: true,
          afterModifyPosition: true,
        })
      ).to.be.true
    })

    it('succeeds for all hooks', async () => {
      expect(
        // 0x1111...
        await hooks.isValidHookAddress('0xF000000000000000000000000000000000000000', {
          beforeSwap: true,
          afterSwap: true,
          beforeModifyPosition: true,
          afterModifyPosition: true,
        })
      ).to.be.true
    })

    it('fails when address invalid for before swap', async () => {
      // 0x0011...
      expect(
        await hooks.isValidHookAddress('0x3000000000000000000000000000000000000000', {
          beforeSwap: true,
          afterSwap: false,
          beforeModifyPosition: false,
          afterModifyPosition: false,
        })
      ).to.be.false
    })

    it('fails when address invalid for after swap', async () => {
      // 0x1011...
      expect(
        await hooks.isValidHookAddress('0xB000000000000000000000000000000000000000', {
          beforeSwap: false,
          afterSwap: true,
          beforeModifyPosition: false,
          afterModifyPosition: false,
        })
      ).to.be.false
    })

    it('fails when address invalid for all hooks', async () => {
      // 0x1011...
      expect(
        await hooks.isValidHookAddress('0xC000000000000000000000000000000000000000', {
          beforeSwap: true,
          afterSwap: true,
          beforeModifyPosition: true,
          afterModifyPosition: true,
        })
      ).to.be.false
    })

    it('fails when address invalid for no hooks', async () => {
      // 0x1010...
      expect(
        await hooks.isValidHookAddress('0xA000000000000000000000000000000000000000', {
          beforeSwap: false,
          afterSwap: false,
          beforeModifyPosition: false,
          afterModifyPosition: false,
        })
      ).to.be.false
    })

    it('gas cost of validateHookAddress', async () => {
      // 0x1010...
      await snapshotGasCost(
        hooks.getGasCostOfValidateHookAddress('0xA000000000000000000000000000000000000000', {
          beforeSwap: false,
          afterSwap: false,
          beforeModifyPosition: false,
          afterModifyPosition: false,
        })
      )
    })
  })

  describe('#shouldCall', () => {
    it('succeeds for shouldCallBeforeSwap', async () => {
      expect(await hooks.shouldCallBeforeSwap('0x8000000000000000000000000000000000000000')).to.be.true
    })
    it('fails for shouldCallBeforeSwap', async () => {
      expect(await hooks.shouldCallBeforeSwap('0x3000000000000000000000000000000000000000')).to.be.false
    })
    it('succeeds for shouldCallAfterSwap', async () => {
      expect(await hooks.shouldCallAfterSwap('0x4000000000000000000000000000000000000000')).to.be.true
    })
    it('fails for shouldCallAfterSwap', async () => {
      expect(await hooks.shouldCallAfterSwap('0x8000000000000000000000000000000000000000')).to.be.false
    })
    it('succeeds for shouldCallBeforeModifyPosition', async () => {
      expect(await hooks.shouldCallBeforeModifyPosition('0x2000000000000000000000000000000000000000')).to.be.true
    })
    it('fails for shouldCallBeforeModifyPosition', async () => {
      expect(await hooks.shouldCallBeforeModifyPosition('0xC000000000000000000000000000000000000000')).to.be.false
    })
    it('succeeds for shouldCallAfterModifyPosition', async () => {
      expect(await hooks.shouldCallAfterModifyPosition('0x1000000000000000000000000000000000000000')).to.be.true
    })
    it('fails for shouldCallAfterModifyPosition', async () => {
      expect(await hooks.shouldCallAfterModifyPosition('0xC000000000000000000000000000000000000000')).to.be.false
    })
    it('succeeds for all hooks', async () => {
      expect(await hooks.shouldCallBeforeSwap('0xF000000000000000000000000000000000000000')).to.be.true
      expect(await hooks.shouldCallAfterSwap('0xF000000000000000000000000000000000000000')).to.be.true
      expect(await hooks.shouldCallBeforeModifyPosition('0xF000000000000000000000000000000000000000')).to.be.true
      expect(await hooks.shouldCallAfterModifyPosition('0xF000000000000000000000000000000000000000')).to.be.true
    })
    it('succeeds for no hooks', async () => {
      expect(await hooks.shouldCallBeforeSwap('0x0000000000000000000000000000000000000000')).to.be.false
      expect(await hooks.shouldCallAfterSwap('0x0000000000000000000000000000000000000000')).to.be.false
      expect(await hooks.shouldCallBeforeModifyPosition('0x0000000000000000000000000000000000000000')).to.be.false
      expect(await hooks.shouldCallAfterModifyPosition('0x0000000000000000000000000000000000000000')).to.be.false
    })
    it('gas cost of shouldCall', async () => {
      await snapshotGasCost(hooks.getGasCostOfShouldCall('0x0000000000000000000000000000000000000000'))
    })
  })
})
