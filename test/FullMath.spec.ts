import { ethers } from 'hardhat'
import { FullMathTest } from '../typechain/FullMathTest'
import { expect } from './shared/expect'
import { Decimal } from 'decimal.js'

const {
  BigNumber,
  constants: { MaxUint256 },
} = ethers
const Q128 = BigNumber.from(2).pow(128)

Decimal.config({ toExpNeg: -500, toExpPos: 500 })

describe('FullMath', () => {
  let fullMath: FullMathTest
  before('deploy FullMathTest', async () => {
    const factory = await ethers.getContractFactory('FullMathTest')
    fullMath = (await factory.deploy()) as FullMathTest
  })

  function pseudoRandomBigNumber() {
    return BigNumber.from(new Decimal(MaxUint256.toString()).mul(Math.random().toString()).round().toString())
  }

  // tiny fuzzer. unskip to run
  it.skip('check a bunch of random inputs against JS implementation', async () => {
    // generates random inputs
    const tests = Array(1_000)
      .fill(null)
      .map(() => {
        return {
          x: pseudoRandomBigNumber(),
          y: pseudoRandomBigNumber(),
          d: pseudoRandomBigNumber(),
        }
      })
      .map(({ x, y, d }) => {
        return {
          input: {
            x,
            y,
            d,
          },
          floored: fullMath.mulDiv(x, y, d),
          ceiled: fullMath.mulDivRoundingUp(x, y, d),
        }
      })

    await Promise.all(
      tests.map(async ({ input: { x, y, d }, floored, ceiled }) => {
        if (d.eq(0)) {
          await expect(floored).to.be.reverted
          await expect(ceiled).to.be.reverted
          return
        }

        if (x.eq(0) || y.eq(0)) {
          await expect(floored).to.eq(0)
          await expect(ceiled).to.eq(0)
        } else if (x.mul(y).div(d).gt(MaxUint256)) {
          await expect(floored).to.be.reverted
          await expect(ceiled).to.be.reverted
        } else {
          expect(await floored).to.eq(x.mul(y).div(d))
          expect(await ceiled).to.eq(
            x
              .mul(y)
              .div(d)
              .add(x.mul(y).mod(d).gt(0) ? 1 : 0)
          )
        }
      })
    )
  })
})
