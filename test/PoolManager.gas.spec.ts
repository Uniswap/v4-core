// import { ethers, waffle } from 'hardhat'
// import { Wallet } from 'ethers'
// import { PoolManager, PoolSwapTest, PoolDonateTest, PoolModifyPositionTest } from '../typechain'
// import { expect } from './shared/expect'
// import { ADDRESS_ZERO } from './shared/constants'
//
// import { tokensFixture } from './shared/fixtures'
// import snapshotGasCost from '@uniswap/snapshot-gas-cost'
//
// import {
//   expandTo18Decimals,
//   FeeAmount,
//   getMinTick,
//   encodeSqrtPriceX96,
//   TICK_SPACINGS,
//   SwapFunction,
//   ModifyPositionFunction,
//   DonateFunction,
//   getMaxTick,
//   MaxUint128,
//   SwapToPriceFunction,
//   MIN_SQRT_RATIO,
//   getPoolId,
// } from './shared/utilities'
//
// const { constants } = ethers
//
// const createFixtureLoader = waffle.createFixtureLoader
//
// type AsyncReturnType<T extends (...args: any) => any> = T extends (...args: any) => Promise<infer U>
//   ? U
//   : T extends (...args: any) => infer U
//   ? U
//   : any
//
// describe('PoolManager gas tests', () => {
//   let wallet: Wallet, other: Wallet
//
//   let loadFixture: ReturnType<typeof createFixtureLoader>
//
//   before('create fixture loader', async () => {
//     ;[wallet, other] = await (ethers as any).getSigners()
//     loadFixture = createFixtureLoader([wallet, other])
//   })
//
//   const startingPrice = encodeSqrtPriceX96(100001, 100000)
//   const startingTick = 0
//   const feeAmount = FeeAmount.MEDIUM
//   const tickSpacing = TICK_SPACINGS[feeAmount]
//   const minTick = getMinTick(tickSpacing)
//   const maxTick = getMaxTick(tickSpacing)
//
//   describe('ERC20 tokens', () => {
//     const gasTestFixture = async ([wallet]: Wallet[]) => {
//       const { currency0, currency1 } = await tokensFixture()
//
//       const singletonPoolFactory = await ethers.getContractFactory('PoolManager')
//       const swapTestFactory = await ethers.getContractFactory('PoolSwapTest')
//       const donateTestFactory = await ethers.getContractFactory('PoolDonateTest')
//       const mintTestFactory = await ethers.getContractFactory('PoolModifyPositionTest')
//       const CONTROLLER_GAS_LIMIT = 50000
//       const manager = (await singletonPoolFactory.deploy(CONTROLLER_GAS_LIMIT)) as PoolManager
//
//       const swapTest = (await swapTestFactory.deploy(manager.address)) as PoolSwapTest
//       const donateTest = (await donateTestFactory.deploy(manager.address)) as PoolDonateTest
//       const modifyPositionTest = (await mintTestFactory.deploy(manager.address)) as PoolModifyPositionTest
//
//       for (const token of [currency0, currency1]) {
//         for (const spender of [swapTest, donateTest, modifyPositionTest]) {
//           await token.connect(wallet).approve(spender.address, constants.MaxUint256)
//         }
//       }
//
//       const poolKey = {
//         currency0: currency0.address,
//         currency1: currency1.address,
//         fee: FeeAmount.MEDIUM,
//         tickSpacing: 60,
//         hooks: ADDRESS_ZERO,
//       }
//
//       const swapExact0For1: SwapFunction = (amount, to, sqrtPriceLimitX96) => {
//         return swapTest.swap(
//           poolKey,
//           {
//             zeroForOne: true,
//             amountSpecified: amount,
//             sqrtPriceLimitX96: sqrtPriceLimitX96 ?? MIN_SQRT_RATIO.add(1),
//           },
//           {
//             withdrawTokens: true,
//             settleUsingTransfer: true,
//           },
//           '0x00'
//         )
//       }
//       const swapToHigherPrice: SwapToPriceFunction = (sqrtPriceX96, to) => {
//         return swapTest.swap(
//           poolKey,
//           {
//             zeroForOne: false,
//             amountSpecified: MaxUint128,
//             sqrtPriceLimitX96: sqrtPriceX96,
//           },
//           {
//             withdrawTokens: true,
//             settleUsingTransfer: true,
//           },
//           '0x00'
//         )
//       }
//       const swapToLowerPrice: SwapToPriceFunction = (sqrtPriceX96, to) => {
//         return swapTest.swap(
//           poolKey,
//           {
//             zeroForOne: true,
//             amountSpecified: MaxUint128,
//             sqrtPriceLimitX96: sqrtPriceX96,
//           },
//           {
//             withdrawTokens: true,
//             settleUsingTransfer: true,
//           },
//           '0x00'
//         )
//       }
//       const modifyPosition: ModifyPositionFunction = (tickLower, tickUpper, liquidityDelta) => {
//         return modifyPositionTest.modifyPosition(
//           poolKey,
//           {
//             tickLower,
//             tickUpper,
//             liquidityDelta,
//           },
//           '0x00'
//         )
//       }
//       const donate: DonateFunction = (amount0, amount1) => {
//         return donateTest.donate(poolKey, amount0, amount1, '0x00')
//       }
//       const getSlot0 = async () => {
//         return await manager.getSlot0(getPoolId(poolKey))
//       }
//
//       await manager.initialize(poolKey, encodeSqrtPriceX96(1, 1), '0x00')
//
//       await modifyPosition(minTick, maxTick, expandTo18Decimals(2))
//
//       await swapExact0For1(expandTo18Decimals(1), wallet.address)
//       await swapToHigherPrice(startingPrice, wallet.address)
//
//       const { tick, sqrtPriceX96 } = await getSlot0()
//
//       expect(tick).to.eq(startingTick)
//       expect(sqrtPriceX96).to.eq(startingPrice)
//
//       return { manager, getSlot0, poolKey, swapExact0For1, modifyPosition, donate, swapToHigherPrice, swapToLowerPrice }
//     }
//
//     let swapExact0For1: SwapFunction
//     let swapToHigherPrice: SwapToPriceFunction
//     let swapToLowerPrice: SwapToPriceFunction
//     let manager: PoolManager
//     let modifyPosition: ModifyPositionFunction
//     let donate: DonateFunction
//     let getSlot0: AsyncReturnType<typeof gasTestFixture>['getSlot0']
//     let poolKey: AsyncReturnType<typeof gasTestFixture>['poolKey']
//
//     beforeEach('load the fixture', async () => {
//       ;({ swapExact0For1, manager, modifyPosition, donate, swapToHigherPrice, swapToLowerPrice, getSlot0, poolKey } =
//         await loadFixture(gasTestFixture))
//     })
//
//     describe('#initialize', () => {
//       it('initialize pool with no hooks and no protocol fee', async () => {
//         let currency0 = wallet.address
//         let currency1 = other.address
//
//         ;[currency0, currency1] = currency0 < currency1 ? [currency0, currency1] : [currency1, currency0]
//
//         const altPoolKey = {
//           currency0,
//           currency1,
//           fee: FeeAmount.MEDIUM,
//           tickSpacing: 60,
//           hooks: '0x0000000000000000000000000000000000000000',
//         }
//         await snapshotGasCost(manager.initialize(altPoolKey, encodeSqrtPriceX96(1, 1), '0x00'))
//       })
//     })
//
//     describe('#swapExact0For1', () => {
//       it('first swap in block with no tick movement', async () => {
//         await snapshotGasCost(swapExact0For1(2000, wallet.address))
//         expect((await getSlot0()).sqrtPriceX96).to.not.eq(startingPrice)
//         expect((await getSlot0()).tick).to.eq(startingTick)
//       })
//
//       it('first swap in block moves tick, no initialized crossings', async () => {
//         await snapshotGasCost(swapExact0For1(expandTo18Decimals(1).div(10000), wallet.address))
//         expect((await getSlot0()).tick).to.eq(startingTick - 1)
//       })
//
//       it('second swap in block with no tick movement', async () => {
//         await swapExact0For1(expandTo18Decimals(1).div(10000), wallet.address)
//         expect((await getSlot0()).tick).to.eq(startingTick - 1)
//         await snapshotGasCost(swapExact0For1(2000, wallet.address))
//         expect((await getSlot0()).tick).to.eq(startingTick - 1)
//       })
//
//       it('second swap in block moves tick, no initialized crossings', async () => {
//         await swapExact0For1(1000, wallet.address)
//         expect((await getSlot0()).tick).to.eq(startingTick)
//         await snapshotGasCost(swapExact0For1(expandTo18Decimals(1).div(10000), wallet.address))
//         expect((await getSlot0()).tick).to.eq(startingTick - 1)
//       })
//
//       it('first swap in block, large swap, no initialized crossings', async () => {
//         await snapshotGasCost(swapExact0For1(expandTo18Decimals(10), wallet.address))
//         expect((await getSlot0()).tick).to.eq(-35787)
//       })
//
//       it('first swap in block, large swap crossing several initialized ticks', async () => {
//         await modifyPosition(startingTick - 3 * tickSpacing, startingTick - tickSpacing, expandTo18Decimals(1))
//         await modifyPosition(startingTick - 4 * tickSpacing, startingTick - 2 * tickSpacing, expandTo18Decimals(1))
//         expect((await getSlot0()).tick).to.eq(startingTick)
//         await snapshotGasCost(swapExact0For1(expandTo18Decimals(1), wallet.address))
//         expect((await getSlot0()).tick).to.be.lt(startingTick - 4 * tickSpacing) // we crossed the last tick
//       })
//
//       it('first swap in block, large swap crossing a single initialized tick', async () => {
//         await modifyPosition(minTick, startingTick - 2 * tickSpacing, expandTo18Decimals(1))
//         await snapshotGasCost(swapExact0For1(expandTo18Decimals(1), wallet.address))
//         expect((await getSlot0()).tick).to.be.lt(startingTick - 2 * tickSpacing) // we crossed the last tick
//       })
//
//       it('second swap in block, large swap crossing several initialized ticks', async () => {
//         await modifyPosition(startingTick - 3 * tickSpacing, startingTick - tickSpacing, expandTo18Decimals(1))
//         await modifyPosition(startingTick - 4 * tickSpacing, startingTick - 2 * tickSpacing, expandTo18Decimals(1))
//         await swapExact0For1(expandTo18Decimals(1).div(10000), wallet.address)
//         await snapshotGasCost(swapExact0For1(expandTo18Decimals(1), wallet.address))
//         expect((await getSlot0()).tick).to.be.lt(startingTick - 4 * tickSpacing)
//       })
//
//       it('second swap in block, large swap crossing a single initialized tick', async () => {
//         await modifyPosition(minTick, startingTick - 2 * tickSpacing, expandTo18Decimals(1))
//         await swapExact0For1(expandTo18Decimals(1).div(10000), wallet.address)
//         expect((await getSlot0()).tick).to.be.gt(startingTick - 2 * tickSpacing) // we didn't cross the initialized tick
//         await snapshotGasCost(swapExact0For1(expandTo18Decimals(1), wallet.address))
//         expect((await getSlot0()).tick).to.be.lt(startingTick - 2 * tickSpacing) // we crossed the last tick
//       })
//     })
//
//     describe('#mint', () => {
//       for (const { description, tickLower, tickUpper } of [
//         {
//           description: 'around current price',
//           tickLower: startingTick - tickSpacing,
//           tickUpper: startingTick + tickSpacing,
//         },
//         {
//           description: 'below current price',
//           tickLower: startingTick - 2 * tickSpacing,
//           tickUpper: startingTick - tickSpacing,
//         },
//         {
//           description: 'above current price',
//           tickLower: startingTick + tickSpacing,
//           tickUpper: startingTick + 2 * tickSpacing,
//         },
//       ]) {
//         describe(description, () => {
//           it('new position mint first in range', async () => {
//             await snapshotGasCost(modifyPosition(tickLower, tickUpper, expandTo18Decimals(1)))
//           })
//           it('add to position existing', async () => {
//             await modifyPosition(tickLower, tickUpper, expandTo18Decimals(1))
//             await snapshotGasCost(modifyPosition(tickLower, tickUpper, expandTo18Decimals(1)))
//           })
//           it('second position in same range', async () => {
//             await modifyPosition(tickLower, tickUpper, expandTo18Decimals(1))
//             await snapshotGasCost(modifyPosition(tickLower, tickUpper, expandTo18Decimals(1)))
//           })
//         })
//       }
//     })
//
//     // describe('#burn', () => {
//     //   for (const { description, tickLower, tickUpper } of [
//     //     {
//     //       description: 'around current price',
//     //       tickLower: startingTick - tickSpacing,
//     //       tickUpper: startingTick + tickSpacing,
//     //     },
//     //     {
//     //       description: 'below current price',
//     //       tickLower: startingTick - 2 * tickSpacing,
//     //       tickUpper: startingTick - tickSpacing,
//     //     },
//     //     {
//     //       description: 'above current price',
//     //       tickLower: startingTick + tickSpacing,
//     //       tickUpper: startingTick + 2 * tickSpacing,
//     //     },
//     //   ]) {
//     //     describe(description, () => {
//     //       const liquidityAmount = expandTo18Decimals(1)
//     //       beforeEach('mint a position', async () => {
//     //         await modifyPosition( tickLower, tickUpper, liquidityAmount)
//     //       })
//     //
//     //       it('burn when only position using ticks', async () => {
//     //         await snapshotGasCost(pool.burn(tickLower, tickUpper, expandTo18Decimals(1)))
//     //       })
//     //       it('partial position burn', async () => {
//     //         await snapshotGasCost(pool.burn(tickLower, tickUpper, expandTo18Decimals(1).div(2)))
//     //       })
//     //       it('entire position burn but other positions are using the ticks', async () => {
//     //         await mint(other.address, tickLower, tickUpper, expandTo18Decimals(1))
//     //         await snapshotGasCost(pool.burn(tickLower, tickUpper, expandTo18Decimals(1)))
//     //       })
//     //       it('burn entire position after some time passes', async () => {
//     //         await manager.advanceTime(1)
//     //         await snapshotGasCost(pool.burn(tickLower, tickUpper, expandTo18Decimals(1)))
//     //       })
//     //     })
//     //   }
//     // })
//
//     // describe('#poke', () => {
//     //   const tickLower = startingTick - tickSpacing
//     //   const tickUpper = startingTick + tickSpacing
//     //
//     //   it('best case', async () => {
//     //     await modifyPosition( tickLower, tickUpper, expandTo18Decimals(1))
//     //     await swapExact0For1(expandTo18Decimals(1).div(100), wallet.address)
//     //     await pool.burn(tickLower, tickUpper, 0)
//     //     await swapExact0For1(expandTo18Decimals(1).div(100), wallet.address)
//     //     await snapshotGasCost(pool.burn(tickLower, tickUpper, 0))
//     //   })
//     // })
//   })
//
//   describe('Native Tokens', () => {
//     const gasTestFixture = async ([wallet]: Wallet[]) => {
//       const { currency1 } = await tokensFixture()
//
//       const singletonPoolFactory = await ethers.getContractFactory('PoolManager')
//       const swapTestFactory = await ethers.getContractFactory('PoolSwapTest')
//       const donateTestFactory = await ethers.getContractFactory('PoolDonateTest')
//       const mintTestFactory = await ethers.getContractFactory('PoolModifyPositionTest')
//       const CONTROLLER_GAS_LIMIT = 50000
//       const manager = (await singletonPoolFactory.deploy(CONTROLLER_GAS_LIMIT)) as PoolManager
//
//       const swapTest = (await swapTestFactory.deploy(manager.address)) as PoolSwapTest
//       const donateTest = (await donateTestFactory.deploy(manager.address)) as PoolDonateTest
//       const modifyPositionTest = (await mintTestFactory.deploy(manager.address)) as PoolModifyPositionTest
//
//       for (const spender of [swapTest, donateTest, modifyPositionTest]) {
//         await currency1.connect(wallet).approve(spender.address, constants.MaxUint256)
//       }
//
//       const poolKey = {
//         currency0: ADDRESS_ZERO,
//         currency1: currency1.address,
//         fee: FeeAmount.MEDIUM,
//         tickSpacing: 60,
//         hooks: ADDRESS_ZERO,
//       }
//
//       const swapExact0For1: SwapFunction = (amount, to, sqrtPriceLimitX96) => {
//         return swapTest.swap(
//           poolKey,
//           {
//             zeroForOne: true,
//             amountSpecified: amount,
//             sqrtPriceLimitX96: sqrtPriceLimitX96 ?? MIN_SQRT_RATIO.add(1),
//           },
//           {
//             withdrawTokens: true,
//             settleUsingTransfer: true,
//           },
//           '0x00',
//           {
//             value: amount,
//           }
//         )
//       }
//       const swapToHigherPrice: SwapToPriceFunction = (sqrtPriceX96, to) => {
//         return swapTest.swap(
//           poolKey,
//           {
//             zeroForOne: false,
//             amountSpecified: MaxUint128,
//             sqrtPriceLimitX96: sqrtPriceX96,
//           },
//           {
//             withdrawTokens: true,
//             settleUsingTransfer: true,
//           },
//           '0x00'
//         )
//       }
//       const swapToLowerPrice: SwapToPriceFunction = (sqrtPriceX96, to) => {
//         return swapTest.swap(
//           poolKey,
//           {
//             zeroForOne: true,
//             amountSpecified: MaxUint128,
//             sqrtPriceLimitX96: sqrtPriceX96,
//           },
//           {
//             withdrawTokens: true,
//             settleUsingTransfer: true,
//           },
//           '0x00',
//           {
//             value: MaxUint128,
//           }
//         )
//       }
//       const modifyPosition: ModifyPositionFunction = (tickLower, tickUpper, liquidityDelta) => {
//         return modifyPositionTest.modifyPosition(
//           poolKey,
//           {
//             tickLower,
//             tickUpper,
//             liquidityDelta,
//           },
//           '0x00',
//           { value: liquidityDelta }
//         )
//       }
//       const donate: DonateFunction = (amount0, amount1) => {
//         return donateTest.donate(poolKey, amount0, amount1, '0x00', { value: amount0 })
//       }
//       const getSlot0 = async () => {
//         return await manager.getSlot0(getPoolId(poolKey))
//       }
//
//       await manager.initialize(poolKey, encodeSqrtPriceX96(1, 1), '0x00')
//
//       await modifyPosition(minTick, maxTick, expandTo18Decimals(2))
//
//       await swapExact0For1(expandTo18Decimals(1), wallet.address)
//       await swapToHigherPrice(startingPrice, wallet.address)
//
//       const { tick, sqrtPriceX96 } = await getSlot0()
//
//       expect(tick).to.eq(startingTick)
//       expect(sqrtPriceX96).to.eq(startingPrice)
//
//       return { manager, getSlot0, poolKey, swapExact0For1, modifyPosition, donate, swapToHigherPrice, swapToLowerPrice }
//     }
//
//     let swapExact0For1: SwapFunction
//     let swapToHigherPrice: SwapToPriceFunction
//     let swapToLowerPrice: SwapToPriceFunction
//     let manager: PoolManager
//     let modifyPosition: ModifyPositionFunction
//     let donate: DonateFunction
//     let getSlot0: AsyncReturnType<typeof gasTestFixture>['getSlot0']
//     let poolKey: AsyncReturnType<typeof gasTestFixture>['poolKey']
//
//     beforeEach('load the fixture', async () => {
//       ;({ swapExact0For1, manager, modifyPosition, donate, swapToHigherPrice, swapToLowerPrice, getSlot0, poolKey } =
//         await loadFixture(gasTestFixture))
//     })
//
//     describe('#swapExact0For1', () => {
//       it('first swap in block with no tick movement', async () => {
//         await snapshotGasCost(swapExact0For1(2000, wallet.address))
//         expect((await getSlot0()).sqrtPriceX96).to.not.eq(startingPrice)
//         expect((await getSlot0()).tick).to.eq(startingTick)
//       })
//
//       it('first swap in block moves tick, no initialized crossings', async () => {
//         await snapshotGasCost(swapExact0For1(expandTo18Decimals(1).div(10000), wallet.address))
//         expect((await getSlot0()).tick).to.eq(startingTick - 1)
//       })
//
//       it('second swap in block with no tick movement', async () => {
//         await swapExact0For1(expandTo18Decimals(1).div(10000), wallet.address)
//         expect((await getSlot0()).tick).to.eq(startingTick - 1)
//         await snapshotGasCost(swapExact0For1(2000, wallet.address))
//         expect((await getSlot0()).tick).to.eq(startingTick - 1)
//       })
//
//       it('second swap in block moves tick, no initialized crossings', async () => {
//         await swapExact0For1(1000, wallet.address)
//         expect((await getSlot0()).tick).to.eq(startingTick)
//         await snapshotGasCost(swapExact0For1(expandTo18Decimals(1).div(10000), wallet.address))
//         expect((await getSlot0()).tick).to.eq(startingTick - 1)
//       })
//
//       it('first swap in block, large swap, no initialized crossings', async () => {
//         await snapshotGasCost(swapExact0For1(expandTo18Decimals(10), wallet.address))
//         expect((await getSlot0()).tick).to.eq(-35787)
//       })
//
//       it('first swap in block, large swap crossing several initialized ticks', async () => {
//         await modifyPosition(startingTick - 3 * tickSpacing, startingTick - tickSpacing, expandTo18Decimals(1))
//         await modifyPosition(startingTick - 4 * tickSpacing, startingTick - 2 * tickSpacing, expandTo18Decimals(1))
//         expect((await getSlot0()).tick).to.eq(startingTick)
//         await snapshotGasCost(swapExact0For1(expandTo18Decimals(1), wallet.address))
//         expect((await getSlot0()).tick).to.be.lt(startingTick - 4 * tickSpacing) // we crossed the last tick
//       })
//
//       it('first swap in block, large swap crossing a single initialized tick', async () => {
//         await modifyPosition(minTick, startingTick - 2 * tickSpacing, expandTo18Decimals(1))
//         await snapshotGasCost(swapExact0For1(expandTo18Decimals(1), wallet.address))
//         expect((await getSlot0()).tick).to.be.lt(startingTick - 2 * tickSpacing) // we crossed the last tick
//       })
//
//       it('second swap in block, large swap crossing several initialized ticks', async () => {
//         await modifyPosition(startingTick - 3 * tickSpacing, startingTick - tickSpacing, expandTo18Decimals(1))
//         await modifyPosition(startingTick - 4 * tickSpacing, startingTick - 2 * tickSpacing, expandTo18Decimals(1))
//         await swapExact0For1(expandTo18Decimals(1).div(10000), wallet.address)
//         await snapshotGasCost(swapExact0For1(expandTo18Decimals(1), wallet.address))
//         expect((await getSlot0()).tick).to.be.lt(startingTick - 4 * tickSpacing)
//       })
//
//       it('second swap in block, large swap crossing a single initialized tick', async () => {
//         await modifyPosition(minTick, startingTick - 2 * tickSpacing, expandTo18Decimals(1))
//         await swapExact0For1(expandTo18Decimals(1).div(10000), wallet.address)
//         expect((await getSlot0()).tick).to.be.gt(startingTick - 2 * tickSpacing) // we didn't cross the initialized tick
//         await snapshotGasCost(swapExact0For1(expandTo18Decimals(1), wallet.address))
//         expect((await getSlot0()).tick).to.be.lt(startingTick - 2 * tickSpacing) // we crossed the last tick
//       })
//     })
//
//     describe('#mint', () => {
//       for (const { description, tickLower, tickUpper } of [
//         {
//           description: 'around current price',
//           tickLower: startingTick - tickSpacing,
//           tickUpper: startingTick + tickSpacing,
//         },
//         {
//           description: 'below current price',
//           tickLower: startingTick - 2 * tickSpacing,
//           tickUpper: startingTick - tickSpacing,
//         },
//         {
//           description: 'above current price',
//           tickLower: startingTick + tickSpacing,
//           tickUpper: startingTick + 2 * tickSpacing,
//         },
//       ]) {
//         describe(description, () => {
//           it('new position mint first in range', async () => {
//             await snapshotGasCost(modifyPosition(tickLower, tickUpper, expandTo18Decimals(1)))
//           })
//           it('add to position existing', async () => {
//             await modifyPosition(tickLower, tickUpper, expandTo18Decimals(1))
//             await snapshotGasCost(modifyPosition(tickLower, tickUpper, expandTo18Decimals(1)))
//           })
//           it('second position in same range', async () => {
//             await modifyPosition(tickLower, tickUpper, expandTo18Decimals(1))
//             await snapshotGasCost(modifyPosition(tickLower, tickUpper, expandTo18Decimals(1)))
//           })
//         })
//       }
//     })
//   })
// })
