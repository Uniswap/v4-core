import { Wallet } from 'ethers'
import hre, { ethers, waffle } from 'hardhat'
import { LimitOrderHook, PoolManager, PoolSwapTest, TestERC20 } from '../typechain'
import { expect } from './shared/expect'
import { tokensFixture } from './shared/fixtures'
import { encodeSqrtPriceX96, FeeAmount, getWalletForDeployingHookMask } from './shared/utilities'

const { constants, utils } = ethers

const createFixtureLoader = waffle.createFixtureLoader

interface PoolKey {
  token0: string
  token1: string
  fee: FeeAmount
  tickSpacing: number
  hooks: string
}

describe('LimitOrderHooks', () => {
  let wallet: Wallet, other: Wallet

  let tokens: { token0: TestERC20; token1: TestERC20; token2: TestERC20 }
  let manager: PoolManager
  let limitOrderHook: LimitOrderHook
  let swapTest: PoolSwapTest

  const fixture = async () => {
    const tokens = await tokensFixture()

    const poolManagerFactory = await ethers.getContractFactory('PoolManager')
    const limitOrderHookFactory = await ethers.getContractFactory('LimitOrderHook')
    const swapTestFactory = await ethers.getContractFactory('PoolSwapTest')

    const manager = (await poolManagerFactory.deploy()) as PoolManager

    // find a deployer that will generate a suitable hooks address
    const [hookDeployer, hookAddress] = getWalletForDeployingHookMask(
      {
        beforeInitialize: false,
        afterInitialize: true,
        beforeModifyPosition: false,
        afterModifyPosition: false,
        beforeSwap: false,
        afterSwap: true,
        beforeDonate: false,
        afterDonate: false,
      },
      'test onion mountain stove water behind cloud street robot salad load join'
    )

    ;[wallet] = await (ethers as any).getSigners()
    await wallet.sendTransaction({ to: hookDeployer.address, value: utils.parseEther('1') })

    // deploy the hook and make a contract instance
    await hookDeployer
      .connect(hre.ethers.provider)
      .sendTransaction(limitOrderHookFactory.getDeployTransaction(manager.address))
    const limitOrderHook = limitOrderHookFactory.attach(hookAddress) as LimitOrderHook

    const result = {
      tokens,
      manager,
      limitOrderHook,
      swapTest: (await swapTestFactory.deploy(manager.address)) as PoolSwapTest,
    }

    for (const token of [tokens.token0, tokens.token1, tokens.token2]) {
      for (const spender of [result.swapTest, limitOrderHook]) {
        await token.connect(wallet).approve(spender.address, constants.MaxUint256)
        await token.connect(wallet).transfer(other.address, utils.parseEther('1'))
        await token.connect(other).approve(spender.address, constants.MaxUint256)
      }
    }

    return result
  }

  let loadFixture: ReturnType<typeof createFixtureLoader>
  before('create fixture loader', async () => {
    ;[wallet, other] = await (ethers as any).getSigners()

    loadFixture = createFixtureLoader([wallet, other])
  })

  beforeEach('deploy fixture', async () => {
    ;({ tokens, manager, limitOrderHook, swapTest } = await loadFixture(fixture))
  })

  it('bytecode size', async () => {
    expect(((await waffle.provider.getCode(limitOrderHook.address)).length - 2) / 2).to.matchSnapshot()
  })

  let key: PoolKey

  beforeEach('initialize pool with limit order hook', async () => {
    await manager.initialize(
      (key = {
        token0: tokens.token0.address,
        token1: tokens.token1.address,
        fee: FeeAmount.MEDIUM,
        tickSpacing: 60,
        hooks: limitOrderHook.address,
      }),
      encodeSqrtPriceX96(1, 1)
    )
  })

  describe('hook is initialized', async () => {
    describe('#getTickLowerLast', () => {
      it('works when the price is 1', async () => {
        expect(await limitOrderHook.getTickLowerLast(key)).to.eq(0)
      })

      it('works when the price is not 1', async () => {
        const otherKey = {
          ...key,
          tickSpacing: 61,
        }
        await manager.initialize(otherKey, encodeSqrtPriceX96(10, 1))
        expect(await limitOrderHook.getTickLowerLast(otherKey)).to.eq(22997)
      })
    })

    it('#epochNext', async () => {
      expect(await limitOrderHook.epochNext()).to.eq(1)
    })
  })

  describe('#place', async () => {
    it('#ZeroLiquidity', async () => {
      const tickLower = 0
      const zeroForOne = true
      const liquidity = 0
      await expect(limitOrderHook.place(key, tickLower, zeroForOne, liquidity)).to.be.revertedWith('ZeroLiquidity()')
    })

    describe('zeroForOne = true', async () => {
      const zeroForOne = true
      const liquidity = 100

      it('works from the right boundary of the current range', async () => {
        const tickLower = key.tickSpacing
        await limitOrderHook.place(key, tickLower, zeroForOne, liquidity)
        expect(await limitOrderHook.getEpoch(key, tickLower, zeroForOne)).to.eq(1)
      })

      it('works from the left boundary of the current range', async () => {
        const tickLower = 0
        await limitOrderHook.place(key, tickLower, zeroForOne, liquidity)
        expect(await limitOrderHook.getEpoch(key, tickLower, zeroForOne)).to.eq(1)
      })

      it('#CrossedRange', async () => {
        const tickLower = -key.tickSpacing
        await expect(limitOrderHook.place(key, tickLower, zeroForOne, liquidity)).to.be.revertedWith('CrossedRange()')
      })

      it('#InRange', async () => {
        await swapTest.swap(
          key,
          {
            zeroForOne: false,
            amountSpecified: 1, // swapping is free, there's no liquidity in the pool, so we only need to specify 1 wei
            sqrtPriceLimitX96: encodeSqrtPriceX96(1, 1).add(1),
          },
          {
            withdrawTokens: true,
            settleUsingTransfer: true,
          }
        )

        const tickLower = 0
        await expect(limitOrderHook.place(key, tickLower, zeroForOne, liquidity)).to.be.revertedWith('InRange()')
      })
    })

    describe('zeroForOne = false', async () => {
      const zeroForOne = false
      const liquidity = 100

      it('works up until the left boundary of the current range', async () => {
        const tickLower = -key.tickSpacing
        await limitOrderHook.place(key, tickLower, zeroForOne, liquidity)
        expect(await limitOrderHook.getEpoch(key, tickLower, zeroForOne)).to.eq(1)
      })

      it('#CrossedRange', async () => {
        const tickLower = 0
        await expect(limitOrderHook.place(key, tickLower, zeroForOne, liquidity)).to.be.revertedWith('CrossedRange()')
      })

      it('#InRange', async () => {
        await swapTest.swap(
          key,
          {
            zeroForOne: true,
            amountSpecified: 1, // swapping is free, there's no liquidity in the pool, so we only need to specify 1 wei
            sqrtPriceLimitX96: encodeSqrtPriceX96(1, 1).sub(1),
          },
          {
            withdrawTokens: true,
            settleUsingTransfer: true,
          }
        )

        const tickLower = -key.tickSpacing
        await expect(limitOrderHook.place(key, tickLower, zeroForOne, liquidity)).to.be.revertedWith('InRange()')
      })
    })

    it('works with different LPs', async () => {
      const tickLower = key.tickSpacing
      const zeroForOne = true
      const liquidity = 100
      await limitOrderHook.place(key, tickLower, zeroForOne, liquidity)
      await limitOrderHook.connect(other).place(key, tickLower, zeroForOne, liquidity)
      expect(await limitOrderHook.getEpoch(key, tickLower, zeroForOne)).to.eq(1)

      const epochInfo = await limitOrderHook.epochInfos(1)
      expect(epochInfo.token0).to.eq(key.token0)
      expect(epochInfo.token1).to.eq(key.token1)
      expect(epochInfo.token0Total).to.eq(0)
      expect(epochInfo.token1Total).to.eq(0)
      expect(epochInfo.liquidityTotal).to.eq(liquidity * 2)

      expect(await limitOrderHook.getEpochLiquidity(1, wallet.address)).to.eq(liquidity)
      expect(await limitOrderHook.getEpochLiquidity(1, other.address)).to.eq(liquidity)
    })
  })
})
