import { ethers, waffle } from 'hardhat'
import { Wallet } from 'ethers'
import { MockTimePoolManager, PoolSwapTest, PoolMintTest, PoolBurnTest } from '../typechain'
import { expect } from './shared/expect'

import { tokensFixture } from './shared/fixtures'
import snapshotGasCost from './shared/snapshotGasCost'

import {
  expandTo18Decimals,
  FeeAmount,
  getMinTick,
  encodeSqrtPriceX96,
  TICK_SPACINGS,
  SwapFunction,
  MintFunction,
  getMaxTick,
  MaxUint128,
  SwapToPriceFunction,
  MAX_SQRT_RATIO,
  MIN_SQRT_RATIO,
  getPoolId,
} from './shared/utilities'

const { constants } = ethers

const createFixtureLoader = waffle.createFixtureLoader

type AsyncReturnType<T extends (...args: any) => any> = T extends (...args: any) => Promise<infer U>
  ? U
  : T extends (...args: any) => infer U
  ? U
  : any

describe('PoolManager gas tests', () => {
  let wallet: Wallet, other: Wallet

  let loadFixture: ReturnType<typeof createFixtureLoader>

  before('create fixture loader', async () => {
    ;[wallet, other] = await (ethers as any).getSigners()
    loadFixture = createFixtureLoader([wallet, other])
  })

  for (const feeProtocol of [0, 6]) {
    describe(feeProtocol > 0 ? 'fee is on' : 'fee is off', () => {
      const startingPrice = encodeSqrtPriceX96(100001, 100000)
      const startingTick = 0
      const feeAmount = FeeAmount.MEDIUM
      const tickSpacing = TICK_SPACINGS[feeAmount]
      const minTick = getMinTick(tickSpacing)
      const maxTick = getMaxTick(tickSpacing)

      const gasTestFixture = async ([wallet]: Wallet[]) => {
        const { token0, token1 } = await tokensFixture()

        const singletonPoolFactory = await ethers.getContractFactory('MockTimePoolManager')
        const swapTestFactory = await ethers.getContractFactory('PoolSwapTest')
        const mintTestFactory = await ethers.getContractFactory('PoolMintTest')
        const burnTestFactory = await ethers.getContractFactory('PoolBurnTest')
        const manager = (await singletonPoolFactory.deploy()) as MockTimePoolManager

        const swapTest = (await swapTestFactory.deploy(manager.address)) as PoolSwapTest
        const mintTest = (await mintTestFactory.deploy(manager.address)) as PoolMintTest
        const burnTest = (await burnTestFactory.deploy(manager.address)) as PoolBurnTest

        for (const token of [token0, token1]) {
          for (const spender of [swapTest, mintTest, burnTest]) {
            await token.connect(wallet).approve(spender.address, constants.MaxUint256)
          }
        }

        const poolKey = { token0: token0.address, token1: token1.address, fee: FeeAmount.MEDIUM }

        const swapExact0For1: SwapFunction = (amount, to, sqrtPriceLimitX96) => {
          return swapTest.swap(poolKey, {
            zeroForOne: true,
            amountSpecified: amount,
            sqrtPriceLimitX96: sqrtPriceLimitX96 ?? MIN_SQRT_RATIO.add(1),
          })
        }
        const swapToHigherPrice: SwapToPriceFunction = (sqrtPriceX96, to) => {
          return swapTest.swap(poolKey, {
            zeroForOne: false,
            amountSpecified: MaxUint128,
            sqrtPriceLimitX96: sqrtPriceX96,
          })
        }
        const swapToLowerPrice: SwapToPriceFunction = (sqrtPriceX96, to) => {
          return swapTest.swap(poolKey, {
            zeroForOne: true,
            amountSpecified: MaxUint128,
            sqrtPriceLimitX96: sqrtPriceX96,
          })
        }
        const mint: MintFunction = (recipient, tickLower, tickUpper, liquidity) => {
          return mintTest.mint(poolKey, {
            recipient,
            tickLower,
            tickUpper,
            amount: liquidity,
          })
        }
        const getSlot0 = async () => {
          const { slot0 } = await manager.pools(getPoolId(poolKey))
          return slot0
        }

        await manager.initialize(poolKey, encodeSqrtPriceX96(1, 1))
        await manager.setFeeProtocol(poolKey, feeProtocol + feeProtocol * 2 ** 4)
        await manager.increaseObservationCardinalityNext(poolKey, 4)

        await manager.advanceTime(1)

        await mint(wallet.address, minTick, maxTick, expandTo18Decimals(2))

        await swapExact0For1(expandTo18Decimals(1), wallet.address)
        await manager.advanceTime(1)
        await swapToHigherPrice(startingPrice, wallet.address)
        await manager.advanceTime(1)

        const { tick, sqrtPriceX96 } = await getSlot0()

        expect(tick).to.eq(startingTick)
        expect(sqrtPriceX96).to.eq(startingPrice)

        return { manager, getSlot0, poolKey, swapExact0For1, mint, swapToHigherPrice, swapToLowerPrice }
      }

      let swapExact0For1: SwapFunction
      let swapToHigherPrice: SwapToPriceFunction
      let swapToLowerPrice: SwapToPriceFunction
      let manager: MockTimePoolManager
      let mint: MintFunction
      let getSlot0: AsyncReturnType<typeof gasTestFixture>['getSlot0']
      let poolKey: AsyncReturnType<typeof gasTestFixture>['poolKey']

      beforeEach('load the fixture', async () => {
        ;({ swapExact0For1, manager, mint, swapToHigherPrice, swapToLowerPrice, getSlot0, poolKey } = await loadFixture(
          gasTestFixture
        ))
      })

      describe('#swapExact0For1', () => {
        it('first swap in block with no tick movement', async () => {
          await snapshotGasCost(swapExact0For1(2000, wallet.address))
          expect((await getSlot0()).sqrtPriceX96).to.not.eq(startingPrice)
          expect((await getSlot0()).tick).to.eq(startingTick)
        })

        it('first swap in block moves tick, no initialized crossings', async () => {
          await snapshotGasCost(swapExact0For1(expandTo18Decimals(1).div(10000), wallet.address))
          expect((await getSlot0()).tick).to.eq(startingTick - 1)
        })

        it('second swap in block with no tick movement', async () => {
          await swapExact0For1(expandTo18Decimals(1).div(10000), wallet.address)
          expect((await getSlot0()).tick).to.eq(startingTick - 1)
          await snapshotGasCost(swapExact0For1(2000, wallet.address))
          expect((await getSlot0()).tick).to.eq(startingTick - 1)
        })

        it('second swap in block moves tick, no initialized crossings', async () => {
          await swapExact0For1(1000, wallet.address)
          expect((await getSlot0()).tick).to.eq(startingTick)
          await snapshotGasCost(swapExact0For1(expandTo18Decimals(1).div(10000), wallet.address))
          expect((await getSlot0()).tick).to.eq(startingTick - 1)
        })

        it('first swap in block, large swap, no initialized crossings', async () => {
          await snapshotGasCost(swapExact0For1(expandTo18Decimals(10), wallet.address))
          expect((await getSlot0()).tick).to.eq(-35787)
        })

        it('first swap in block, large swap crossing several initialized ticks', async () => {
          await mint(wallet.address, startingTick - 3 * tickSpacing, startingTick - tickSpacing, expandTo18Decimals(1))
          await mint(
            wallet.address,
            startingTick - 4 * tickSpacing,
            startingTick - 2 * tickSpacing,
            expandTo18Decimals(1)
          )
          expect((await getSlot0()).tick).to.eq(startingTick)
          await snapshotGasCost(swapExact0For1(expandTo18Decimals(1), wallet.address))
          expect((await getSlot0()).tick).to.be.lt(startingTick - 4 * tickSpacing) // we crossed the last tick
        })

        it('first swap in block, large swap crossing a single initialized tick', async () => {
          await mint(wallet.address, minTick, startingTick - 2 * tickSpacing, expandTo18Decimals(1))
          await snapshotGasCost(swapExact0For1(expandTo18Decimals(1), wallet.address))
          expect((await getSlot0()).tick).to.be.lt(startingTick - 2 * tickSpacing) // we crossed the last tick
        })

        it('second swap in block, large swap crossing several initialized ticks', async () => {
          await mint(wallet.address, startingTick - 3 * tickSpacing, startingTick - tickSpacing, expandTo18Decimals(1))
          await mint(
            wallet.address,
            startingTick - 4 * tickSpacing,
            startingTick - 2 * tickSpacing,
            expandTo18Decimals(1)
          )
          await swapExact0For1(expandTo18Decimals(1).div(10000), wallet.address)
          await snapshotGasCost(swapExact0For1(expandTo18Decimals(1), wallet.address))
          expect((await getSlot0()).tick).to.be.lt(startingTick - 4 * tickSpacing)
        })

        it('second swap in block, large swap crossing a single initialized tick', async () => {
          await mint(wallet.address, minTick, startingTick - 2 * tickSpacing, expandTo18Decimals(1))
          await swapExact0For1(expandTo18Decimals(1).div(10000), wallet.address)
          expect((await getSlot0()).tick).to.be.gt(startingTick - 2 * tickSpacing) // we didn't cross the initialized tick
          await snapshotGasCost(swapExact0For1(expandTo18Decimals(1), wallet.address))
          expect((await getSlot0()).tick).to.be.lt(startingTick - 2 * tickSpacing) // we crossed the last tick
        })

        it('large swap crossing several initialized ticks after some time passes', async () => {
          await mint(wallet.address, startingTick - 3 * tickSpacing, startingTick - tickSpacing, expandTo18Decimals(1))
          await mint(
            wallet.address,
            startingTick - 4 * tickSpacing,
            startingTick - 2 * tickSpacing,
            expandTo18Decimals(1)
          )
          await swapExact0For1(2, wallet.address)
          await manager.advanceTime(1)
          await snapshotGasCost(swapExact0For1(expandTo18Decimals(1), wallet.address))
          expect((await getSlot0()).tick).to.be.lt(startingTick - 4 * tickSpacing)
        })

        it('large swap crossing several initialized ticks second time after some time passes', async () => {
          await mint(wallet.address, startingTick - 3 * tickSpacing, startingTick - tickSpacing, expandTo18Decimals(1))
          await mint(
            wallet.address,
            startingTick - 4 * tickSpacing,
            startingTick - 2 * tickSpacing,
            expandTo18Decimals(1)
          )
          await swapExact0For1(expandTo18Decimals(1), wallet.address)
          await swapToHigherPrice(startingPrice, wallet.address)
          await manager.advanceTime(1)
          await snapshotGasCost(swapExact0For1(expandTo18Decimals(1), wallet.address))
          expect((await getSlot0()).tick).to.be.lt(tickSpacing * -4)
        })
      })

      describe('#mint', () => {
        for (const { description, tickLower, tickUpper } of [
          {
            description: 'around current price',
            tickLower: startingTick - tickSpacing,
            tickUpper: startingTick + tickSpacing,
          },
          {
            description: 'below current price',
            tickLower: startingTick - 2 * tickSpacing,
            tickUpper: startingTick - tickSpacing,
          },
          {
            description: 'above current price',
            tickLower: startingTick + tickSpacing,
            tickUpper: startingTick + 2 * tickSpacing,
          },
        ]) {
          describe(description, () => {
            it('new position mint first in range', async () => {
              await snapshotGasCost(mint(wallet.address, tickLower, tickUpper, expandTo18Decimals(1)))
            })
            it('add to position existing', async () => {
              await mint(wallet.address, tickLower, tickUpper, expandTo18Decimals(1))
              await snapshotGasCost(mint(wallet.address, tickLower, tickUpper, expandTo18Decimals(1)))
            })
            it('second position in same range', async () => {
              await mint(wallet.address, tickLower, tickUpper, expandTo18Decimals(1))
              await snapshotGasCost(mint(other.address, tickLower, tickUpper, expandTo18Decimals(1)))
            })
            it('add to position after some time passes', async () => {
              await mint(wallet.address, tickLower, tickUpper, expandTo18Decimals(1))
              await manager.advanceTime(1)
              await snapshotGasCost(mint(wallet.address, tickLower, tickUpper, expandTo18Decimals(1)))
            })
          })
        }
      })

      // describe('#burn', () => {
      //   for (const { description, tickLower, tickUpper } of [
      //     {
      //       description: 'around current price',
      //       tickLower: startingTick - tickSpacing,
      //       tickUpper: startingTick + tickSpacing,
      //     },
      //     {
      //       description: 'below current price',
      //       tickLower: startingTick - 2 * tickSpacing,
      //       tickUpper: startingTick - tickSpacing,
      //     },
      //     {
      //       description: 'above current price',
      //       tickLower: startingTick + tickSpacing,
      //       tickUpper: startingTick + 2 * tickSpacing,
      //     },
      //   ]) {
      //     describe(description, () => {
      //       const liquidityAmount = expandTo18Decimals(1)
      //       beforeEach('mint a position', async () => {
      //         await mint(wallet.address, tickLower, tickUpper, liquidityAmount)
      //       })
      //
      //       it('burn when only position using ticks', async () => {
      //         await snapshotGasCost(pool.burn(tickLower, tickUpper, expandTo18Decimals(1)))
      //       })
      //       it('partial position burn', async () => {
      //         await snapshotGasCost(pool.burn(tickLower, tickUpper, expandTo18Decimals(1).div(2)))
      //       })
      //       it('entire position burn but other positions are using the ticks', async () => {
      //         await mint(other.address, tickLower, tickUpper, expandTo18Decimals(1))
      //         await snapshotGasCost(pool.burn(tickLower, tickUpper, expandTo18Decimals(1)))
      //       })
      //       it('burn entire position after some time passes', async () => {
      //         await manager.advanceTime(1)
      //         await snapshotGasCost(pool.burn(tickLower, tickUpper, expandTo18Decimals(1)))
      //       })
      //     })
      //   }
      // })

      // describe('#poke', () => {
      //   const tickLower = startingTick - tickSpacing
      //   const tickUpper = startingTick + tickSpacing
      //
      //   it('best case', async () => {
      //     await mint(wallet.address, tickLower, tickUpper, expandTo18Decimals(1))
      //     await swapExact0For1(expandTo18Decimals(1).div(100), wallet.address)
      //     await pool.burn(tickLower, tickUpper, 0)
      //     await swapExact0For1(expandTo18Decimals(1).div(100), wallet.address)
      //     await snapshotGasCost(pool.burn(tickLower, tickUpper, 0))
      //   })
      // })

      describe('#increaseObservationCardinalityNext', () => {
        it('grow by 1 slot', async () => {
          await snapshotGasCost(manager.increaseObservationCardinalityNext(poolKey, 5))
        })
        it('no op', async () => {
          await snapshotGasCost(manager.increaseObservationCardinalityNext(poolKey, 3))
        })
      })

      describe('#snapshotCumulativesInside', () => {
        it('tick inside', async () => {
          await snapshotGasCost(manager.estimateGas.snapshotCumulativesInside(poolKey, minTick, maxTick))
        })
        it('tick above', async () => {
          await swapToHigherPrice(MAX_SQRT_RATIO.sub(1), wallet.address)
          await snapshotGasCost(manager.estimateGas.snapshotCumulativesInside(poolKey, minTick, maxTick))
        })
        it('tick below', async () => {
          await swapToLowerPrice(MIN_SQRT_RATIO.add(1), wallet.address)
          await snapshotGasCost(manager.estimateGas.snapshotCumulativesInside(poolKey, minTick, maxTick))
        })
      })
    })
  }
})
