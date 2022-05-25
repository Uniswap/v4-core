import snapshotGasCost from '@uniswap/snapshot-gas-cost'
import { ethers, waffle } from 'hardhat'
import { HooksTest } from '../typechain/HooksTest'
import { expect } from './shared/expect'
import { createHookMask } from './shared/utilities'

describe('Hooks', () => {
  let hooks: HooksTest
  const fixture = async () => {
    const factory = await ethers.getContractFactory('HooksTest')
    return (await factory.deploy()) as HooksTest
  }
  beforeEach('deploy HooksTest', async () => {
    hooks = await waffle.loadFixture(fixture)
  })

  /**
   * Tester for our utility function
   */
  describe('#createHookMask', () => {
    it('called nowhere', () => {
      expect(
        createHookMask({
          beforeInitialize: false,
          afterInitialize: false,
          beforeModifyPosition: false,
          afterModifyPosition: false,
          beforeSwap: false,
          afterSwap: false,
          afterDonate: false,
          beforeDonate: false,
        })
      ).to.eq('0x0000000000000000000000000000000000000000')
    })
    it('called everywhere', () => {
      expect(
        createHookMask({
          beforeInitialize: true,
          afterInitialize: true,
          beforeModifyPosition: true,
          afterModifyPosition: true,
          beforeSwap: true,
          afterSwap: true,
          afterDonate: true,
          beforeDonate: true,
        })
      ).to.eq('0xff00000000000000000000000000000000000000')
    })

    it('called every other', () => {
      expect(
        createHookMask({
          beforeInitialize: true,
          afterInitialize: false,
          beforeModifyPosition: true,
          afterModifyPosition: false,
          beforeSwap: true,
          afterSwap: false,
          afterDonate: true,
          beforeDonate: false,
        })
      ).to.eq('0xaa00000000000000000000000000000000000000')
    })
  })

  describe('#validateHookAddress', () => {
    it('succeeds', async () => {
      expect(
        await hooks.validateHookAddress('0x0000000000000000000000000000000000000000', {
          beforeInitialize: false,
          afterInitialize: false,
          beforeModifyPosition: false,
          afterModifyPosition: false,
          beforeSwap: false,
          afterSwap: false,
          beforeDonate: false,
          afterDonate: false,
        })
      )
    })

    it('succeeds for before initialize only', async () => {
      expect(
        // 10000000
        await hooks.validateHookAddress('0x8000000000000000000000000000000000000000', {
          beforeInitialize: true,
          afterInitialize: false,
          beforeModifyPosition: false,
          afterModifyPosition: false,
          beforeSwap: false,
          afterSwap: false,
          beforeDonate: false,
          afterDonate: false,
        })
      )
    })

    it('succeeds for after initialize only', async () => {
      expect(
        // 01000000
        await hooks.validateHookAddress('0x4000000000000000000000000000000000000000', {
          beforeInitialize: false,
          afterInitialize: true,
          beforeModifyPosition: false,
          afterModifyPosition: false,
          beforeSwap: false,
          afterSwap: false,
          beforeDonate: false,
          afterDonate: false,
        })
      )
    })

    it('succeeds for before and after initialize only', async () => {
      expect(
        // 11000000
        await hooks.validateHookAddress('0xC000000000000000000000000000000000000000', {
          beforeInitialize: true,
          afterInitialize: true,
          beforeModifyPosition: false,
          afterModifyPosition: false,
          beforeSwap: false,
          afterSwap: false,
          beforeDonate: false,
          afterDonate: false,
        })
      )
    })

    it('succeeds for before modify position only', async () => {
      expect(
        // 00100000
        await hooks.validateHookAddress('0x2000000000000000000000000000000000000000', {
          beforeInitialize: false,
          afterInitialize: false,
          beforeModifyPosition: true,
          afterModifyPosition: false,
          beforeSwap: false,
          afterSwap: false,
          beforeDonate: false,
          afterDonate: false,
        })
      )
    })

    it('succeeds for after modify position only', async () => {
      expect(
        // 00010000
        await hooks.validateHookAddress('0x1000000000000000000000000000000000000000', {
          beforeInitialize: false,
          afterInitialize: false,
          beforeModifyPosition: false,
          afterModifyPosition: true,
          beforeSwap: false,
          afterSwap: false,
          beforeDonate: false,
          afterDonate: false,
        })
      )
    })

    it('succeeds for before and after modify position only', async () => {
      expect(
        // 00110000
        await hooks.validateHookAddress('0x3000000000000000000000000000000000000000', {
          beforeInitialize: false,
          afterInitialize: false,
          beforeModifyPosition: true,
          afterModifyPosition: true,
          beforeSwap: false,
          afterSwap: false,
          beforeDonate: false,
          afterDonate: false,
        })
      )
    })

    it('succeeds for before swap only', async () => {
      expect(
        // 00001000
        await hooks.validateHookAddress('0x0800000000000000000000000000000000000000', {
          beforeInitialize: false,
          afterInitialize: false,
          beforeModifyPosition: false,
          afterModifyPosition: false,
          beforeSwap: true,
          afterSwap: false,
          beforeDonate: false,
          afterDonate: false,
        })
      )
    })

    it('succeeds for after swap only', async () => {
      expect(
        // 00000100
        await hooks.validateHookAddress('0x0400000000000000000000000000000000000000', {
          beforeInitialize: false,
          afterInitialize: false,
          beforeModifyPosition: false,
          afterModifyPosition: false,
          beforeSwap: false,
          afterSwap: true,
          beforeDonate: false,
          afterDonate: false,
        })
      )
    })

    it('succeeds for before and after swap only', async () => {
      expect(
        // 00001100
        await hooks.validateHookAddress('0x0C00000000000000000000000000000000000000', {
          beforeInitialize: false,
          afterInitialize: false,
          beforeModifyPosition: false,
          afterModifyPosition: false,
          beforeSwap: true,
          afterSwap: true,
          beforeDonate: false,
          afterDonate: false,
        })
      )
    })

    it('succeeds for before donate only', async () => {
      expect(
        // 00000010
        await hooks.validateHookAddress('0x0200000000000000000000000000000000000000', {
          beforeInitialize: false,
          afterInitialize: false,
          beforeModifyPosition: false,
          afterModifyPosition: false,
          beforeSwap: false,
          afterSwap: false,
          beforeDonate: true,
          afterDonate: false,
        })
      )
    })

    it('succeeds for after donate only', async () => {
      expect(
        // 00000001
        await hooks.validateHookAddress('0x0100000000000000000000000000000000000000', {
          beforeInitialize: false,
          afterInitialize: false,
          beforeModifyPosition: false,
          afterModifyPosition: false,
          beforeSwap: false,
          afterSwap: false,
          beforeDonate: false,
          afterDonate: true,
        })
      )
    })

    it('succeeds for before and after donate only', async () => {
      expect(
        // 00000011
        await hooks.validateHookAddress('0x0300000000000000000000000000000000000000', {
          beforeInitialize: false,
          afterInitialize: false,
          beforeModifyPosition: false,
          afterModifyPosition: false,
          beforeSwap: false,
          afterSwap: false,
          beforeDonate: true,
          afterDonate: true,
        })
      )
    })

    it('succeeds for all hooks', async () => {
      expect(
        // 11111111
        await hooks.validateHookAddress('0xFF00000000000000000000000000000000000000', {
          beforeInitialize: true,
          afterInitialize: true,
          beforeModifyPosition: true,
          afterModifyPosition: true,
          beforeSwap: true,
          afterSwap: true,
          beforeDonate: true,
          afterDonate: true,
        })
      )
    })

    it('fails when address invalid for before swap', async () => {
      // 00110000
      await expect(
        hooks.validateHookAddress('0x3000000000000000000000000000000000000000', {
          beforeInitialize: false,
          afterInitialize: false,
          beforeModifyPosition: false,
          afterModifyPosition: false,
          beforeSwap: true,
          afterSwap: false,
          beforeDonate: false,
          afterDonate: false,
        })
      ).to.be.reverted
    })

    it('fails when address invalid for after swap', async () => {
      // 10110000
      await expect(
        hooks.validateHookAddress('0xB000000000000000000000000000000000000000', {
          beforeInitialize: false,
          afterInitialize: false,
          beforeModifyPosition: false,
          afterModifyPosition: false,
          beforeSwap: false,
          afterSwap: true,
          beforeDonate: false,
          afterDonate: false,
        })
      ).to.be.reverted
    })

    it('fails when address invalid for all hooks', async () => {
      // 11000000
      await expect(
        hooks.validateHookAddress('0xC000000000000000000000000000000000000000', {
          beforeInitialize: true,
          afterInitialize: true,
          beforeModifyPosition: true,
          afterModifyPosition: true,
          beforeSwap: true,
          afterSwap: true,
          beforeDonate: true,
          afterDonate: true,
        })
      ).to.be.reverted
    })

    it('fails when address invalid for no hooks', async () => {
      // 10100000
      await expect(
        hooks.validateHookAddress('0xA000000000000000000000000000000000000000', {
          beforeInitialize: false,
          afterInitialize: false,
          beforeModifyPosition: false,
          afterModifyPosition: false,
          beforeSwap: false,
          afterSwap: false,
          beforeDonate: false,
          afterDonate: false,
        })
      ).to.be.reverted
    })

    it('gas cost of validateHookAddress', async () => {
      await snapshotGasCost(
        hooks.getGasCostOfValidateHookAddress('0x0000000000000000000000000000000000000000', {
          beforeInitialize: false,
          afterInitialize: false,
          beforeModifyPosition: false,
          afterModifyPosition: false,
          beforeSwap: false,
          afterSwap: false,
          beforeDonate: false,
          afterDonate: false,
        })
      )
    })
  })

  describe('#shouldCall', () => {
    it('succeeds for shouldCallBeforeInitialize', async () => {
      expect(await hooks.shouldCallBeforeInitialize('0x8000000000000000000000000000000000000000')).to.be.true
    })
    it('fails for shouldCallBeforeInitialize', async () => {
      expect(await hooks.shouldCallBeforeInitialize('0x3000000000000000000000000000000000000000')).to.be.false
    })
    it('succeeds for shouldCallAfterInitialize', async () => {
      expect(await hooks.shouldCallAfterInitialize('0x4000000000000000000000000000000000000000')).to.be.true
    })
    it('fails for shouldCallAfterInitialize', async () => {
      expect(await hooks.shouldCallAfterInitialize('0x8000000000000000000000000000000000000000')).to.be.false
    })
    it('succeeds for shouldCallBeforeModifyPosition', async () => {
      expect(await hooks.shouldCallBeforeModifyPosition('0x2000000000000000000000000000000000000000')).to.be.true
    })
    it('fails for shouldCallBeforeModifyPosition', async () => {
      expect(await hooks.shouldCallBeforeModifyPosition('0x0800000000000000000000000000000000000000')).to.be.false
    })
    it('succeeds for shouldCallAfterModifyPosition', async () => {
      expect(await hooks.shouldCallAfterModifyPosition('0x1000000000000000000000000000000000000000')).to.be.true
    })
    it('fails for shouldCallAfterModifyPosition', async () => {
      expect(await hooks.shouldCallAfterModifyPosition('0x8000000000000000000000000000000000000000')).to.be.false
    })
    it('succeeds for shouldCallBeforeSwap', async () => {
      expect(await hooks.shouldCallBeforeSwap('0x0800000000000000000000000000000000000000')).to.be.true
    })
    it('fails for shouldCallBeforeSwap', async () => {
      expect(await hooks.shouldCallBeforeSwap('0xC000000000000000000000000000000000000000')).to.be.false
    })
    it('succeeds for shouldCallAfterSwap', async () => {
      expect(await hooks.shouldCallAfterSwap('0x0400000000000000000000000000000000000000')).to.be.true
    })
    it('fails for shouldCallAfterSwap', async () => {
      expect(await hooks.shouldCallAfterSwap('0xC000000000000000000000000000000000000000')).to.be.false
    })
    it('succeeds for shouldCallBeforeDonate', async () => {
      expect(await hooks.shouldCallBeforeDonate('0x0200000000000000000000000000000000000000')).to.be.true
    })
    it('fails for shouldCallBeforeDonate', async () => {
      expect(await hooks.shouldCallBeforeDonate('0x0000000000000000000000000000000000000000')).to.be.false
    })
    it('succeeds for shouldCallAfterDonate', async () => {
      expect(await hooks.shouldCallAfterDonate('0x0100000000000000000000000000000000000000')).to.be.true
    })
    it('fails for shouldCallAfterDonate', async () => {
      expect(await hooks.shouldCallAfterDonate('0x0000000000000000000000000000000000000000')).to.be.false
    })
    it('succeeds for all hooks', async () => {
      expect(await hooks.shouldCallBeforeInitialize('0xFF00000000000000000000000000000000000000')).to.be.true
      expect(await hooks.shouldCallAfterInitialize('0xFF00000000000000000000000000000000000000')).to.be.true
      expect(await hooks.shouldCallBeforeSwap('0xFF00000000000000000000000000000000000000')).to.be.true
      expect(await hooks.shouldCallAfterSwap('0xFF00000000000000000000000000000000000000')).to.be.true
      expect(await hooks.shouldCallBeforeModifyPosition('0xFF00000000000000000000000000000000000000')).to.be.true
      expect(await hooks.shouldCallAfterModifyPosition('0xFF00000000000000000000000000000000000000')).to.be.true
    })
    it('succeeds for no hooks', async () => {
      expect(await hooks.shouldCallBeforeInitialize('0x0000000000000000000000000000000000000000')).to.be.false
      expect(await hooks.shouldCallAfterInitialize('0x0000000000000000000000000000000000000000')).to.be.false
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
