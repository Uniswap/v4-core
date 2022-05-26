import { TWAMMTest } from '../typechain/TWAMMTest'
import { BigNumber, BigNumberish, FixedNumber, Wallet } from 'ethers'
import { ethers, waffle } from 'hardhat'
import checkObservationEquals from './shared/checkObservationEquals'
import { expect } from './shared/expect'
import snapshotGasCost from '@uniswap/snapshot-gas-cost'
import { encodeSqrtPriceX96, MaxUint128, MAX_SQRT_RATIO } from './shared/utilities'
import bn from 'bignumber.js'

function toWei(n: string): BigNumber {
  return ethers.utils.parseEther(n)
}

function divX96(n: BigNumber): string {
  return (parseInt(n.toString()) / 2 ** 96).toFixed(7).toString()
}

// TODO: fix precision in quad lib, should be
// MAX_SQRT_PRICE
const MAX_WITH_LOSS = BigNumber.from('1461446703485210103287273052203988790139028504575')

describe('TWAMMMath', () => {
  let twamm: TWAMMTest
  let wallet: Wallet, other: Wallet
  let loadFixture: ReturnType<typeof waffle.createFixtureLoader>

  const twammFixture = async () => {
    const twammTestFactory = await ethers.getContractFactory('TWAMMTest')
    return (await twammTestFactory.deploy(10_000)) as TWAMMTest
  }

  before('create fixture loader', async () => {
    ;[wallet, other] = await (ethers as any).getSigners()
    loadFixture = waffle.createFixtureLoader([wallet, other])
  })

  beforeEach(async () => {
    twamm = await loadFixture(twammFixture)
  })

  describe('#calculateExecutionUpdates outputs the correct results when', () => {
    let secondsElapsedX96: BigNumber
    let sqrtPriceX96: BigNumberish
    let liquidity: BigNumberish
    let fee: BigNumberish
    let tickSpacing: BigNumberish
    let sellRateCurrent0: BigNumberish
    let sellRateCurrent1: BigNumberish

    const Q96 = BigNumber.from(2).pow(96)

    beforeEach(async () => {
      secondsElapsedX96 = BigNumber.from(3600).mul(Q96)
      sqrtPriceX96 = encodeSqrtPriceX96(1, 1)
      liquidity = '1000000000000000000000000'
      fee = '3000'
      tickSpacing = '60'
      sellRateCurrent0 = toWei('1')
      sellRateCurrent1 = toWei('1')
    })

    // Outputting results without FixedPointX96 format to compare more easily with desmos
    // https://www.desmos.com/calculator/aszdsyhxjk
    const TEST_CASES = [
      {
        title: 'price is one, sell rates are equal',
        inputs: {
          sqrtPriceX96: encodeSqrtPriceX96(1, 1),
          sellRate0: toWei('1'),
          sellRate1: toWei('1'),
        },
        outputsDivX96: {
          price: '1.0000000',
          earningsFactor0: '3600.0000000',
          earningsFactor1: '3600.0000000',
        },
      },
      {
        title: 'price is one, sell rate is 5',
        inputs: {
          sqrtPriceX96: encodeSqrtPriceX96(1, 1),
          sellRate0: toWei('5'),
          sellRate1: toWei('1'),
        },
        outputsDivX96: {
          price: '0.9858549',
          earningsFactor0: '3549.0165948',
          earningsFactor1: '3651.9628500',
        },
      },
      {
        title: 'price is one, sell rate is 10',
        inputs: {
          sqrtPriceX96: encodeSqrtPriceX96(1, 1),
          sellRate0: toWei('10'),
          sellRate1: toWei('1'),
        },
        outputsDivX96: {
          price: '0.9687272',
          earningsFactor0: '3487.2827245',
          earningsFactor1: '3717.6111869',
        },
      },
      {
        title: 'price is one, sell rate is 1/5',
        inputs: {
          sqrtPriceX96: encodeSqrtPriceX96(1, 1),
          sellRate0: toWei('1'),
          sellRate1: toWei('5'),
        },
        outputsDivX96: {
          price: '1.0143480',
          earningsFactor0: '3651.9628500',
          earningsFactor1: '3549.0165948',
        },
      },
      {
        title: 'price is one, sell rate is 1/10',
        inputs: {
          sqrtPriceX96: encodeSqrtPriceX96(1, 1),
          sellRate0: toWei('1'),
          sellRate1: toWei('10'),
        },
        outputsDivX96: {
          price: '1.0322824',
          earningsFactor0: '3717.6111869',
          earningsFactor1: '3487.2827245',
        },
      },
      {
        title: 'price is high, sell rate is 1/10',
        inputs: {
          sqrtPriceX96: encodeSqrtPriceX96(123456, 1),
          sellRate0: toWei('1'),
          sellRate1: toWei('10'),
        },
        outputsDivX96: {
          price: '155.1531845',
          earningsFactor0: '196245875.5487389',
          earningsFactor1: '0.0815851',
        },
      },
      {
        title: 'sell rate is extremely large',
        inputs: {
          sqrtPriceX96: encodeSqrtPriceX96(1, 1),
          sellRate0: toWei('100000000'),
          sellRate1: toWei('5'),
        },
        outputsDivX96: {
          price: '0.0002236',
          earningsFactor0: '0.0101778',
          earningsFactor1: '71105772809.0000916',
        },
      },
      {
        title: 'when sell rate is extremely small',
        inputs: {
          sqrtPriceX96: encodeSqrtPriceX96(1, 1),
          sellRate0: toWei('5'),
          sellRate1: toWei('100000000'),
        },
        outputsDivX96: {
          price: '4472.1359550',
          earningsFactor0: '71105772809.0000916',
          earningsFactor1: '0.0101778',
        },
      },
      // TODO: not working - amounts out are incorrect from desmos, not enough precision??
      // {
      //   title: 'sell rates are extremely low compared to pool liquidity',
      //   inputs: {
      //     sqrtPriceX96: encodeSqrtPriceX96(1, 1),
      //     sellRate0: '10000',
      //     sellRate1: '500',
      //   },
      //   outputsDivX96: {
      //     price: '1.0000000',
      //     earningsFactor0: '180.0000000',
      //     earningsFactor1: '72000.0000000',
      //   },
      // },
      // TODO: not working - desmos also is turning up invalid numbers (like negative earnings accumulators)
      // {
      //   title: 'sell rate of 1 wei in a pool with liquidity amounts that accommodates 18 token decimals',
      //   inputs: {
      //     sqrtPriceX96: encodeSqrtPriceX96(1, 1),
      //     sellRate0: '5',
      //     sellRate1: '10000',
      //   },
      //   outputsDivX96: {
      //     price: '1.0000000',
      //     earningsFactor0: '184835683.94',
      //     earningsFactor1: '-88816.04197',
      //   },
      // },
    ]

    for (let testcase of TEST_CASES) {
      it(testcase.title, async () => {
        const results = await twamm.callStatic.calculateExecutionUpdates({
          secondsElapsedX96,
          sqrtPriceX96: testcase.inputs.sqrtPriceX96,
          liquidity,
          sellRateCurrent0: testcase.inputs.sellRate0,
          sellRateCurrent1: testcase.inputs.sellRate1,
        })

        expect(divX96(results.sqrtPriceX96)).to.eq(testcase.outputsDivX96.price)
        expect(divX96(results.earningsFactorPool0)).to.eq(testcase.outputsDivX96.earningsFactor0)
        expect(divX96(results.earningsFactorPool1)).to.eq(testcase.outputsDivX96.earningsFactor1)
      })
    }

    it('gas', async () => {
      await snapshotGasCost(
        twamm.calculateExecutionUpdates({
          secondsElapsedX96,
          sqrtPriceX96,
          liquidity,
          sellRateCurrent0,
          sellRateCurrent1,
        })
      )
    })

    it('returns the sellRatio if pushed beyond the max price', async () => {
      // set low liquidity to push price
      liquidity = '1000000000000000000'
      sellRateCurrent0 = toWei('1')
      sellRateCurrent1 = toWei('10')

      const results = await twamm.callStatic.calculateExecutionUpdates({
        secondsElapsedX96,
        sqrtPriceX96,
        liquidity,
        sellRateCurrent0,
        sellRateCurrent1,
      })
    })

    it('TWAMM trades to the sqrtSellRatio when pushed beyond min price', async () => {
      // set low liquidity to push price
      liquidity = '1000000000000000000'

      sellRateCurrent0 = toWei('10')
      sellRateCurrent1 = toWei('1')

      const results = await twamm.callStatic.calculateExecutionUpdates({
        secondsElapsedX96,
        sqrtPriceX96,
        liquidity,
        sellRateCurrent0,
        sellRateCurrent1,
      })

      // TODO
      // The ending price should approach the sqrtSellRatio
      // const expectedSqrtSellRatioX96 = sellRateCurrent1.div(sellRateCurrent0).mul(Q96)
      // expect(results.sqrtPriceX96).to.eq(expectedSqrtSellRatioX96)

      const expectedAmount = sellRateCurrent0.mul(secondsElapsedX96).div(Q96)

      // the trades should be slightly greater than the expectedAmount?
      expect(results.earningsFactorPool0.mul(divX96(secondsElapsedX96))).to.eq(expectedAmount)
      expect(results.earningsFactorPool1.mul(divX96(secondsElapsedX96))).to.eq(expectedAmount)
    })

    it('TWAMM trades pushes the price to the max part of the curve', async () => {
      // set low liquidity
      liquidity = '1000000'
      // to push price to max part of the curve, sell lots of token1
      sellRateCurrent0 = toWei('1')
      sellRateCurrent1 = toWei('10')

      const results = await twamm.callStatic.calculateExecutionUpdates({
        secondsElapsedX96,
        sqrtPriceX96,
        liquidity,
        sellRateCurrent0,
        sellRateCurrent1,
      })

      // TODO
      // The ending price should approach the sqrtSellRatio

      // const expectedSqrtSellRatioX96 = sellRateCurrent1.div(sellRateCurrent0).mul(fixedPoint)
      // expect(results.sqrtPriceX96).to.eq(expectedSqrtSellRatioX96)
      // twamm is trading with itself bc liquidity low
      const expectedAmount0 = sellRateCurrent1.mul(secondsElapsedX96).div(Q96)
      const expectedAmount1 = sellRateCurrent0.mul(secondsElapsedX96).div(Q96)

      // expect(results.sqrtPriceX96).to.eq(MAX_WITH_LOSS)
      // expect(results.earningsAmount0).to.eq(expectedAmount0)
      // expect(results.earningsAmount1).to.eq(expectedAmount1)
    })

    // TODO: Even though the price should fall to the min, it overflows.
    it('TWAMM trades pushes the price to the min part of the curve', async () => {
      // set low liquidity
      liquidity = '100000000000000000000'
      // todo to push price to lowest part of the curve, sell lots of token0
      sellRateCurrent0 = toWei('30000')
      sellRateCurrent1 = toWei('1')

      const results = await twamm.callStatic.calculateExecutionUpdates({
        secondsElapsedX96,
        sqrtPriceX96,
        liquidity,
        sellRateCurrent0,
        sellRateCurrent1,
      })

      const expectedAmount0 = sellRateCurrent1.mul(secondsElapsedX96).div(Q96)
      const expectedAmount1 = sellRateCurrent0.mul(secondsElapsedX96).div(Q96)

      // TODO
      // check earnings amounts
    })
  })

  describe('#calculateTimeBetweenTicks outputs the correct results when', () => {
    let liquidity: BigNumber
    let sqrtPriceStartX96: BigNumber
    let sqrtPriceEndX96: BigNumber
    let sellRateCurrent0: BigNumber
    let sellRateCurrent1: BigNumber

    beforeEach(() => {
      sqrtPriceStartX96 = encodeSqrtPriceX96(1, 1)
      sqrtPriceEndX96 = encodeSqrtPriceX96(2, 1)
      liquidity = BigNumber.from('1000000000000000000000000')
      sellRateCurrent0 = toWei('1')
      sellRateCurrent1 = toWei('100')
    })

    it('returns the correct result', async () => {
      expect(
        await twamm.callStatic.calculateTimeBetweenTicks(
          liquidity,
          sqrtPriceStartX96,
          sqrtPriceEndX96,
          sellRateCurrent0,
          sellRateCurrent1
        )
        // 333077535900883608001926988272645 / Q96 ~= 4204.029543
      ).to.eq('333077535900883608001926988272645')
    })

    it('gas', async () => {
      await snapshotGasCost(
        twamm.calculateTimeBetweenTicks(
          liquidity,
          sqrtPriceStartX96,
          sqrtPriceEndX96,
          sellRateCurrent0,
          sellRateCurrent1
        )
      )
    })
  })
})
