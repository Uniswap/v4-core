import { TWAMMTest } from '../typechain/TWAMMTest'
import { BigNumber, BigNumberish, FixedNumber, Wallet } from 'ethers'
import { ethers, waffle } from 'hardhat'
import checkObservationEquals from './shared/checkObservationEquals'
import { expect } from './shared/expect'
import snapshotGasCost from '@uniswap/snapshot-gas-cost'
import { encodeSqrtPriceX96, expandTo18Decimals, MaxUint128, MAX_SQRT_RATIO, MIN_SQRT_RATIO } from './shared/utilities'
import bn from 'bignumber.js'

function divX96(n: BigNumber, precision: number = 7): string {
  return (parseInt(n.toString()) / 2 ** 96).toFixed(precision).toString()
}

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
      sellRateCurrent0 = expandTo18Decimals(1)
      sellRateCurrent1 = expandTo18Decimals(1)
    })

    // Outputting results without FixedPointX96 format to compare more easily with desmos
    // https://www.desmos.com/calculator/aszdsyhxjk
    const TEST_CASES = [
      {
        title: 'price is one, sell rates are equal',
        inputs: {
          sqrtPriceX96: encodeSqrtPriceX96(1, 1),
          sellRate0: expandTo18Decimals(1),
          sellRate1: expandTo18Decimals(1),
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
          sellRate0: expandTo18Decimals(5),
          sellRate1: expandTo18Decimals(1),
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
          sellRate0: expandTo18Decimals(10),
          sellRate1: expandTo18Decimals(1),
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
          sellRate0: expandTo18Decimals(1),
          sellRate1: expandTo18Decimals(5),
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
          sellRate0: expandTo18Decimals(1),
          sellRate1: expandTo18Decimals(10),
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
          sellRate0: expandTo18Decimals(1),
          sellRate1: expandTo18Decimals(10),
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
          sellRate0: expandTo18Decimals(100000000),
          sellRate1: expandTo18Decimals(5),
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
          sellRate0: expandTo18Decimals(5),
          sellRate1: expandTo18Decimals(100000000),
        },
        outputsDivX96: {
          price: '4472.1359550',
          earningsFactor0: '71105772809.0000916',
          earningsFactor1: '0.0101778',
        },
      },
      // TODO: last 2 tests slightly off from Wolfram (desmos fails to be able to handle these numbers). Write
      // integration tests for these
      {
        title: 'sell rates are extremely low compared to pool liquidity',
        inputs: {
          sqrtPriceX96: encodeSqrtPriceX96(1, 1),
          sellRate0: '10000',
          sellRate1: '5',
        },
        outputsDivX96: {
          price: '1.0000000',
          earningsFactor0: '3600.0000000',
          earningsFactor1: '3599.9999981',
        },
      },
      {
        title: 'sell rate of 1 wei in a pool with liquidity amounts that accommodates 18 token decimals',
        inputs: {
          sqrtPriceX96: encodeSqrtPriceX96(1, 1),
          sellRate0: '5',
          sellRate1: '10000',
        },
        outputsDivX96: {
          price: '1.0000000',
          earningsFactor0: '3600.0000007',
          earningsFactor1: '3600.0000000',
        },
      },
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
        twamm.gasSnapshotCalculateExecutionUpdates({
          secondsElapsedX96,
          sqrtPriceX96,
          liquidity,
          sellRateCurrent0,
          sellRateCurrent1,
        })
      )
    })

    describe('#calculateExecutionUpdates with extreme sell ratios', async () => {
      secondsElapsedX96 = BigNumber.from(3600).mul(Q96)
      sqrtPriceX96 = encodeSqrtPriceX96(1, 1)
      fee = '3000'
      tickSpacing = '60'
      let sellRateCurrent0: BigNumber
      let sellRateCurrent1: BigNumber
      let liquidity: string

      it('sells large amounts of token1', async () => {
        liquidity = '1000000000000000000000000'
        sellRateCurrent0 = BigNumber.from('1')
        sellRateCurrent1 = BigNumber.from('340256786836388094059056965639774460900')

        const results = await twamm.callStatic.calculateExecutionUpdates({
          secondsElapsedX96,
          sqrtPriceX96,
          liquidity,
          sellRateCurrent0,
          sellRateCurrent1,
        })
        // TODO error
        const error = 60
        expect(divX96(results.sqrtPriceX96, 0)).to.eql(BigNumber.from('1223127075048864708').add(error).toString())
        // wolfram
        // 1223127075048864708.72893792449
      })

      it('sells large amounts of token0', async () => {
        liquidity = '1000000000000000000000000'
        sellRateCurrent0 = BigNumber.from('340256786836388094059056965639774460900')
        sellRateCurrent1 = BigNumber.from('1')
        const results = await twamm.callStatic.calculateExecutionUpdates({
          secondsElapsedX96,
          sqrtPriceX96,
          liquidity,
          sellRateCurrent0,
          sellRateCurrent1,
        })
        expect(divX96(results.sqrtPriceX96)).to.eql('0.0000000')
        // wolfram
        // 0.000000000000000000817576
        // basically 0
      })

      it('sets the end price to the max price', async () => {
        liquidity = '1000000000000000000000000'
        // the sqrtSellRatio is greater than the maxEndPrice
        sellRateCurrent0 = BigNumber.from('1')
        sellRateCurrent1 = BigNumber.from('6402567868363880940590569656397744609000')
        const results = await twamm.callStatic.calculateExecutionUpdates({
          secondsElapsedX96,
          sqrtPriceX96,
          liquidity,
          sellRateCurrent0,
          sellRateCurrent1,
        })
        const maxPrice = divX96(MAX_SQRT_RATIO)
        expect(divX96(results.sqrtPriceX96)).to.eql(maxPrice)
      })

      it('sets the end price to the min price', async () => {
        liquidity = '1000000000000000000000000'
        // the sqrtSellRatio is less than the min price
        sellRateCurrent0 = BigNumber.from('6402567868363880940590569656397744609000')
        sellRateCurrent1 = BigNumber.from('1')
        const results = await twamm.callStatic.calculateExecutionUpdates({
          secondsElapsedX96,
          sqrtPriceX96,
          liquidity,
          sellRateCurrent0,
          sellRateCurrent1,
        })
        const minPrice = divX96(MIN_SQRT_RATIO)
        expect(divX96(results.sqrtPriceX96)).to.eql(minPrice)
      })

      it('sets the end price to the max price instead of the sqrtSellRatio when low liquidity', async () => {
        liquidity = '1000000'
        // the sqrtSellRatio is greater than the max price
        sellRateCurrent0 = BigNumber.from('1')
        sellRateCurrent1 = BigNumber.from('6402567868363880940590569656397744609000')
        const results = await twamm.callStatic.calculateExecutionUpdates({
          secondsElapsedX96,
          sqrtPriceX96,
          liquidity,
          sellRateCurrent0,
          sellRateCurrent1,
        })
        const maxPrice = divX96(MAX_SQRT_RATIO)
        expect(divX96(results.sqrtPriceX96)).to.eql(maxPrice)
      })

      it('sets the end price to the min price instead of the sqrtSellRatio when low liquidity', async () => {
        liquidity = '1000000'
        // the sqrtSellRatio is less than the min price
        sellRateCurrent0 = BigNumber.from('6402567868363880940590569656397744609000')
        sellRateCurrent1 = BigNumber.from('1')
        const results = await twamm.callStatic.calculateExecutionUpdates({
          secondsElapsedX96,
          sqrtPriceX96,
          liquidity,
          sellRateCurrent0,
          sellRateCurrent1,
        })
        const minPrice = divX96(MIN_SQRT_RATIO)
        expect(divX96(results.sqrtPriceX96)).to.eql(minPrice)
      })
    })

    describe('with insufficient liquidity', () => {
      describe('excess token0', () => {
        const liquidity = '100'
        const sellRateCurrent0 = expandTo18Decimals(10)
        const sellRateCurrent1 = expandTo18Decimals(1)

        it('returns the sellRatio as the new sqrtPriceX96', async () => {
          const results = await twamm.callStatic.calculateExecutionUpdates({
            secondsElapsedX96,
            sqrtPriceX96,
            liquidity,
            sellRateCurrent0,
            sellRateCurrent1,
          })

          expect(results.sqrtPriceX96).to.equal(encodeSqrtPriceX96(sellRateCurrent1, sellRateCurrent0))
        })

        it('returns earnings roughly equal to the amount of tokens selling', async () => {
          const results = await twamm.callStatic.calculateExecutionUpdates({
            secondsElapsedX96,
            sqrtPriceX96,
            liquidity,
            sellRateCurrent0,
            sellRateCurrent1,
          })

          const earningsAmountPerSecondPool0 = results.earningsFactorPool0
            .mul(sellRateCurrent0)
            .div(divX96(secondsElapsedX96, 0))
            .div(Q96)
          const earningsAmountPerSecondPool1 = results.earningsFactorPool1
            .mul(sellRateCurrent1)
            .div(divX96(secondsElapsedX96, 0))
            .div(Q96)

          // earnings should be approximately equal to the amounts selling of the respective token
          expect(earningsAmountPerSecondPool0).to.eq(sellRateCurrent1)
          expect(earningsAmountPerSecondPool1).to.eq(sellRateCurrent0.sub(1))
        })
      })

      describe('excess token0', () => {
        const liquidity = '100'
        const sellRateCurrent0 = expandTo18Decimals(1)
        const sellRateCurrent1 = expandTo18Decimals(10)

        it('returns the sellRatio as the new sqrtPriceX96', async () => {
          const results = await twamm.callStatic.calculateExecutionUpdates({
            secondsElapsedX96,
            sqrtPriceX96,
            liquidity,
            sellRateCurrent0,
            sellRateCurrent1,
          })

          expect(results.sqrtPriceX96).to.equal(encodeSqrtPriceX96(sellRateCurrent1, sellRateCurrent0))
        })

        it('returns earnings roughly equal to the amount of tokens selling', async () => {
          const results = await twamm.callStatic.calculateExecutionUpdates({
            secondsElapsedX96,
            sqrtPriceX96,
            liquidity,
            sellRateCurrent0,
            sellRateCurrent1,
          })

          const earningsAmountPerSecondPool0 = results.earningsFactorPool0
            .mul(sellRateCurrent0)
            .div(divX96(secondsElapsedX96, 0))
            .div(Q96)
          const earningsAmountPerSecondPool1 = results.earningsFactorPool1
            .mul(sellRateCurrent1)
            .div(divX96(secondsElapsedX96, 0))
            .div(Q96)

          // earnings should be approximately equal to the amounts selling of the respective token
          expect(earningsAmountPerSecondPool0).to.eq(sellRateCurrent1.sub(1))
          expect(earningsAmountPerSecondPool1).to.eq(sellRateCurrent0)
        })
      })
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
      sellRateCurrent0 = expandTo18Decimals(1)
      sellRateCurrent1 = expandTo18Decimals(100)
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
        twamm.gasSnapshotCalculateTimeBetweenTicks(
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
