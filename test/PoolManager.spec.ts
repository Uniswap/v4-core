import { Wallet } from 'ethers'
import { ethers, waffle } from 'hardhat'
import { PoolManager, TestERC20 } from '../typechain'
import { expect } from './shared/expect'
import { tokensFixture } from './shared/fixtures'
import snapshotGasCost from './shared/snapshotGasCost'
import { encodeSqrtPriceX96, FeeAmount, getPoolId } from './shared/utilities'

const createFixtureLoader = waffle.createFixtureLoader

describe.only('PoolManager', () => {
  let wallet: Wallet, other: Wallet

  let singleton: PoolManager
  let tokens: { token0: TestERC20; token1: TestERC20; token2: TestERC20 }
  const fixture = async () => {
    const singletonPoolFactory = await ethers.getContractFactory('PoolManager')
    const tokens = await tokensFixture()
    return {
      singleton: (await singletonPoolFactory.deploy()) as PoolManager,
      tokens,
    }
  }

  let loadFixture: ReturnType<typeof createFixtureLoader>
  before('create fixture loader', async () => {
    ;[wallet, other] = await (ethers as any).getSigners()

    loadFixture = createFixtureLoader([wallet, other])
  })

  beforeEach('deploy fixture', async () => {
    ;({ singleton, tokens } = await loadFixture(fixture))
  })

  it('bytecode size', async () => {
    expect(((await waffle.provider.getCode(singleton.address)).length - 2) / 2).to.matchSnapshot()
  })

  describe('#initialize', async () => {
    it('initializes a pool', async () => {
      await singleton.initialize(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
        },
        encodeSqrtPriceX96(10, 1)
      )

      const {
        slot0: { sqrtPriceX96 },
      } = await singleton.pools(
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
        singleton.initialize(
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
        singleton.mint(
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
      await singleton.initialize(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
        },
        encodeSqrtPriceX96(1, 1)
      )

      await singleton.mint(
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
      await singleton.initialize(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
        },
        encodeSqrtPriceX96(1, 1)
      )

      await snapshotGasCost(
        singleton.mint(
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
        singleton.swap(
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
      await singleton.initialize(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
        },
        encodeSqrtPriceX96(1, 1)
      )
      await singleton.swap(
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
      await singleton.initialize(
        {
          token0: tokens.token0.address,
          token1: tokens.token1.address,
          fee: FeeAmount.MEDIUM,
        },
        encodeSqrtPriceX96(1, 1)
      )
      await snapshotGasCost(
        singleton.swap(
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
