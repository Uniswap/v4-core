import { Wallet } from 'ethers'
import { ethers, waffle } from 'hardhat'
import { PoolManager, TestERC20, PoolManagerTest, PoolSwapTest, PoolMintTest, PoolBurnTest } from '../typechain'
import { expect } from './shared/expect'
import { tokensFixture } from './shared/fixtures'
import snapshotGasCost from './shared/snapshotGasCost'
import { encodeSqrtPriceX96, expandTo18Decimals, FeeAmount, getPoolId } from './shared/utilities'

const createFixtureLoader = waffle.createFixtureLoader

const { constants } = ethers

describe.only('PoolManager', () => {
  let wallet: Wallet, other: Wallet

  let manager: PoolManager
  let lockTest: PoolManagerTest
  let swapTest: PoolSwapTest
  let mintTest: PoolMintTest
  let burnTest: PoolBurnTest
  let tokens: { token0: TestERC20; token1: TestERC20; token2: TestERC20 }
  const fixture = async () => {
    const singletonPoolFactory = await ethers.getContractFactory('PoolManager')
    const managerTestFactory = await ethers.getContractFactory('PoolManagerTest')
    const swapTestFactory = await ethers.getContractFactory('PoolSwapTest')
    const mintTestFactory = await ethers.getContractFactory('PoolMintTest')
    const burnTestFactory = await ethers.getContractFactory('PoolBurnTest')
    const tokens = await tokensFixture()
    const manager = (await singletonPoolFactory.deploy()) as PoolManager

    const result = {
      manager,
      lockTest: (await managerTestFactory.deploy()) as PoolManagerTest,
      swapTest: (await swapTestFactory.deploy(manager.address)) as PoolSwapTest,
      mintTest: (await mintTestFactory.deploy(manager.address)) as PoolMintTest,
      burnTest: (await burnTestFactory.deploy(manager.address)) as PoolBurnTest,
      tokens,
    }

    for (const token of [tokens.token0, tokens.token1, tokens.token2]) {
      for (const spender of [result.swapTest, result.mintTest, result.burnTest]) {
        await token.connect(wallet).approve(spender.address, constants.MaxUint256)
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
    ;({ manager, tokens, lockTest, mintTest, burnTest, swapTest } = await loadFixture(fixture))
  })

  it('bytecode size', async () => {
    expect(((await waffle.provider.getCode(manager.address)).length - 2) / 2).to.matchSnapshot()
  })

  describe('#lock', () => {
    it('no-op lock is ok', async () => {
      await lockTest.lock(manager.address)
    })

    it('gas overhead of no-op lock', async () => {
      await snapshotGasCost(lockTest.lock(manager.address))
    })
  })

  describe('#initialize', async () => {
    it('initializes a pool', async () => {
      await manager.initialize(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
        },
        encodeSqrtPriceX96(10, 1)
      )

      const {
        slot0: { sqrtPriceX96 },
      } = await manager.pools(
        getPoolId({
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
        })
      )
      expect(sqrtPriceX96).to.eq(encodeSqrtPriceX96(10, 1))
    })

    it('gas cost', async () => {
      await snapshotGasCost(
        manager.initialize(
          {
            token0: tokens.token0.address,
            token1: tokens.token1.address,
            fee: FeeAmount.MEDIUM,
          },
          encodeSqrtPriceX96(10, 1)
        )
      )
    })
  })

  describe('#mint', async () => {
    it('reverts if pool not initialized', async () => {
      await expect(
        mintTest.mint(
          {
            token0: tokens.token0.address,
            token1: tokens.token1.address,
            fee: FeeAmount.MEDIUM,
          },
          {
            tickLower: 0,
            tickUpper: 60,
            amount: 100,
            recipient: wallet.address,
          }
        )
      ).to.be.revertedWith('I')
    })

    it('succeeds if pool is initialized', async () => {
      await manager.initialize(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
        },
        encodeSqrtPriceX96(1, 1)
      )

      await mintTest.mint(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
        },
        {
          tickLower: 0,
          tickUpper: 60,
          amount: 100,
          recipient: wallet.address,
        }
      )
    })

    it('gas cost', async () => {
      await manager.initialize(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
        },
        encodeSqrtPriceX96(1, 1)
      )

      await snapshotGasCost(
        mintTest.mint(
          {
            token0: tokens.token0.address,
            token1: tokens.token1.address,
            fee: FeeAmount.MEDIUM,
          },
          {
            tickLower: 0,
            tickUpper: 60,
            amount: 100,
            recipient: wallet.address,
          }
        )
      )
    })
  })

  describe('#swap', () => {
    it('fails if pool is not initialized', async () => {
      await expect(
        swapTest.swap(
          {
            token0: tokens.token0.address,
            token1: tokens.token1.address,
            fee: FeeAmount.MEDIUM,
          },
          {
            amountSpecified: 100,
            sqrtPriceLimitX96: encodeSqrtPriceX96(1, 2),
            zeroForOne: true,
          }
        )
      ).to.be.revertedWith('I')
    })
    it('succeeds if pool is initialized', async () => {
      await manager.initialize(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
        },
        encodeSqrtPriceX96(1, 1)
      )
      await swapTest.swap(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
        },
        {
          amountSpecified: 100,
          sqrtPriceLimitX96: encodeSqrtPriceX96(1, 2),
          zeroForOne: true,
        }
      )
    })
    it('gas', async () => {
      await manager.initialize(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
        },
        encodeSqrtPriceX96(1, 1)
      )

      await swapTest.swap(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
        },
        {
          amountSpecified: 100,
          sqrtPriceLimitX96: encodeSqrtPriceX96(1, 2),
          zeroForOne: true,
        }
      )

      await snapshotGasCost(
        swapTest.swap(
          {
            token0: tokens.token0.address,
            token1: tokens.token1.address,
            fee: FeeAmount.MEDIUM,
          },
          {
            amountSpecified: 100,
            sqrtPriceLimitX96: encodeSqrtPriceX96(1, 4),
            zeroForOne: true,
          }
        )
      )
    })
    it('gas for swap against liquidity', async () => {
      await manager.initialize(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
        },
        encodeSqrtPriceX96(1, 1)
      )
      await mintTest.mint(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
        },
        {
          tickLower: -120,
          tickUpper: 120,
          amount: expandTo18Decimals(1),
          recipient: wallet.address,
        }
      )

      await swapTest.swap(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
        },
        {
          amountSpecified: 100,
          sqrtPriceLimitX96: encodeSqrtPriceX96(1, 2),
          zeroForOne: true,
        }
      )

      await snapshotGasCost(
        swapTest.swap(
          {
            token0: tokens.token0.address,
            token1: tokens.token1.address,
            fee: FeeAmount.MEDIUM,
          },
          {
            amountSpecified: 100,
            sqrtPriceLimitX96: encodeSqrtPriceX96(1, 4),
            zeroForOne: true,
          }
        )
      )
    })
  })
})
