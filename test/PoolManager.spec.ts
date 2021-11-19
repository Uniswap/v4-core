import { Wallet } from 'ethers'
import { ethers, waffle } from 'hardhat'
import { PoolManager, TestERC20, PoolManagerTest } from '../typechain'
import { expect } from './shared/expect'
import { tokensFixture } from './shared/fixtures'
import snapshotGasCost from './shared/snapshotGasCost'
import { encodeSqrtPriceX96, FeeAmount, getPoolId } from './shared/utilities'

const createFixtureLoader = waffle.createFixtureLoader

describe.only('PoolManager', () => {
  let wallet: Wallet, other: Wallet

  let manager: PoolManager
  let managerTest: PoolManagerTest
  let tokens: { token0: TestERC20; token1: TestERC20; token2: TestERC20 }
  const fixture = async () => {
    const singletonPoolFactory = await ethers.getContractFactory('PoolManager')
    const managerTestFactory = await ethers.getContractFactory('PoolManagerTest')
    const tokens = await tokensFixture()
    return {
      manager: (await singletonPoolFactory.deploy()) as PoolManager,
      managerTest: (await managerTestFactory.deploy()) as PoolManagerTest,
      tokens,
    }
  }

  let loadFixture: ReturnType<typeof createFixtureLoader>
  before('create fixture loader', async () => {
    ;[wallet, other] = await (ethers as any).getSigners()

    loadFixture = createFixtureLoader([wallet, other])
  })

  beforeEach('deploy fixture', async () => {
    ;({ manager, tokens, managerTest } = await loadFixture(fixture))
  })

  it('bytecode size', async () => {
    expect(((await waffle.provider.getCode(manager.address)).length - 2) / 2).to.matchSnapshot()
  })

  describe('#lock', () => {
    it('no-op lock is ok', async () => {
      await managerTest.lock(manager.address)
    })

    it('gas overhead of no-op lock', async () => {
      await snapshotGasCost(managerTest.lock(manager.address))
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

  describe.skip('#mint', async () => {
    it('reverts if pool not initialized', async () => {
      await expect(
        manager.mint(
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

      await manager.mint(
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
        manager.mint(
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

  describe.skip('#swap', () => {
    it('fails if pool is not initialized', async () => {
      await expect(
        manager.swap(
          {
            token0: tokens.token0.address,
            token1: tokens.token1.address,
            fee: FeeAmount.MEDIUM,
          },
          {
            amountSpecified: 100,
            sqrtPriceLimitX96: encodeSqrtPriceX96(100, 1),
            zeroForOne: true,
          }
        )
      ).to.be.revertedWith('I')
    })
    it('succeeds if pool is not initialized', async () => {
      await manager.initialize(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
        },
        encodeSqrtPriceX96(1, 1)
      )
      await manager.swap(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
        },
        {
          amountSpecified: 100,
          sqrtPriceLimitX96: encodeSqrtPriceX96(1, 100),
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
      await snapshotGasCost(
        manager.swap(
          {
            token0: tokens.token0.address,
            token1: tokens.token1.address,
            fee: FeeAmount.MEDIUM,
          },
          {
            amountSpecified: 100,
            sqrtPriceLimitX96: encodeSqrtPriceX96(1, 100),
            zeroForOne: true,
          }
        )
      )
    })
  })
})
