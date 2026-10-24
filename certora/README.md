## Verification Overview

The current directory contains Certora's formal verification of UniswapV4 protocol.
Certora's security report for UniswapV4 core could be found in this link:
https://certora.cdn.prismic.io/certora/Zt0HQhoQrfVKl0Hb_UniswapV4coreSecurityReportbyCertora-Final-.pdf

In this directory you will find several subdirectories:

1. **specs** - Contains all the specification files that were written by Certora for the UniswapV4 core protocol. Some files merely contain definitions or functions that serve as summarizations. They are being used in the primary specs that contain rules. There are different rules-containing specs files for different contracts, such as tests for libraries, or rules for a specific function in the PoolManager, like swap() or modifyLiquidity().

2. **helpers** - Contains helper contracts that either introduce new Solidity getter functions, or contracts that serve as tests for libraries, i.e. they implement an external function that calls internal library functions.

3. **patches** - Contains a list of git patch files that record changes to the source code, which are applied before the verification in order to resolve some Prover technical issues.
   It's worth noting that these modifications to the code are rather minor and are needed to bypass some internal analysis issues.
   Essentially, they do not change the meaning of the code, as they replace the optimized inline-assembly with its original Solidity counterpart. The equivalence between the two verions could be easily proven.
   In order to apply/revert the patches, one could simply run the munge/unmungh.sh script located in thescripts sub directory.
   The patches are not needed for every verification job, but rather for the main PoolManager contract. Some libraries verifications do not require the code patches to be applied.

4. **confs** - Contains Prover configuration files for the verification of different contracts in this repository. The main configuration files are used to verify the PoolManager contract, but there also smaller ones for library testing.

5. **scripts** - Contains all the necessary run scripts to execute the spec files on the Certora Prover. These scripts composed of a run command of Certora Prover, together with a configuration (conf) file that introduces all the custom settings per each run.

</br>

---

## Certora Prover installation Instructions

Refer to the Certora Prover official docs for installing it:
https://docs.certora.com/en/latest/docs/user-guide/install.html

General running instrcutions could also be found in the docs:
https://docs.certora.com/en/latest/docs/user-guide/running.html

## Running Instructions

To run a verification job:

1. Open terminal and `cd` your way to the main directory in the Uniswap repository.

2. If this is the first time running a job on this repository, make sure to 'munge' the code in order to apply changes to the source code to avoid Prover issues.
   Simply execute

```sh
    sh certora/scripts/munge.sh
```

in order to apply those. This operation needs to be executed only once.
**Make sure not to push these changes to your working repository.** The changes should only be local and could be reverted anytime by running `unmunge.sh` script.
If the code is already munged, continue to step 3.

3. Make sure you're in the Uniswap main directory (`pwd` is main dir).

4. Run the script you'd like to get results for. Example:
   `sh
sh certora/scripts/Libraries.sh
`
   </br>

---

</br>

---

## ERC20 summarization

All implementations of IERC20 token interface were replaced by a common, simplified behavior,
that is programmed within CVL. That is, the storage variables and the transfer/approve functions are implemented via ghost and CVL functions, respectviely. Here we narrow down the verification scope to simple ERC20 implementations, that maintain basic integrity rules (for example, sum of all balances is equal to total supply).
The implementation is found in `specs/CVLERC20.spec`.

## Exttload summarization

All transient storage read and write ops of the currency deltas were replaced by CVL simple implementation. Therefore, we have access to the
currency deltas directly from CVL. The implementation is found in `specs/CurrencyDeltaSummary.spec`.

## TickMath summarization

The TickMath library functions, which convert between price ticks and square root of a price, were summarized using monotonic ghost functions. The summary axioms are incorportated in `specs/TickMathSummary.spec` and were verified using an actual computation of the source code functions for every relevant input (valid tick and sqrt price, between the minimum and maximum bounds).

## Verified Contracts

A list of contracts in the verification scope
</br>

#### PoolManager

The main contract of UniswapV4 core.

sh certora/scripts/PoolManager_X.sh - generic rules about PoolManager

#### TickBitmapTest

Wrapper contract for `TickBitmap` library.

#### SwapMathTest

Wrapper contract for `SwapMath` library.

#### SqrtPriceMathTest

Wrapper contract for `SqrtPriceMath` library.

#### ProtocolFeeLibraryTest

Wrapper contract for `ProtocolFeeLibrary` library.

#### StateLibraryTest

Wrapper contract for `StateLibrary` library.

</br>

## List of specs

### Common

- **CVLMath.spec**: Basic mathematical library with summarizations for `mulDiv` operations.
- **Foundry.spec**: Basic spec file for foundry integration with the Prover.
- **TickMathDefinitions.spec**: Definitions of `TickMath` in CVL.

### PoolManager

- setup -**HooksNONDET.spec**: Non-deterministic view (NONDET) summaries for all external hook calls.

- **Accounting_modifyLiquidity.spec**: Position accounting rules for modifyLiquidity() function.
- **Accounting_swap.spec**: Position accounting rules for swap() function.
- **CurrencyDeltaSummary.spec**: A summarization for transient storage currency deltas
- **CurrencyDeltaTest.spec**: An equivalence test between `CurrencyDelta` library and CVL summarization in `CurrencyDeltaSummary.spec`.
- **CVLERC20.spec**: ERC20 interface implementation in CVL.
- **extsload.spec**: Summarizations for `extsload` and `exttload` library functions.
- **FullMathSummary.spec**: Summarizations of `FullMath` library functions.
- **HooksDeltas.spec**: Rules that involve currency deltas imposed by hooks.
- **HooksDispatch.spec**: Dispatcher summaries for all external hook calls.
- **HooksNONDET.spec**: Non-deterministic view (NONDET) summaries for all external hook calls.
- **IUnlockCallback.spec**: Dispatcher summary for the unlock `callback` function.
- **Liquidity.spec**: A spec that includes definitions for position liquidites and position worth in tokens.
- **lock.spec**: Invariants that help proving the correlation between the sum of all currency deltas and the locked state of the manager.
- **PoolManager.spec**: Several rules for the PoolManager.
- **PoolStateTickBitmap.spec**: Summarization of the `TickBitmap` library.
- **ProtocolFeeLibrary.spec**: Summarization of the `ProtocolFeeLibrary` library.
- **ProtocolFeeLibraryTest.spec**: Test rules for the `ProtocolFeeLibrary` library.
- **SqrtPriceMathDetSummary.spec**: Deterministic summarization for the `SqrtPriceMath` functions, without any axioms (unspecified behavior).
- **SqrtPriceMathRealSummary.spec**: Deterministic summarization for the `SqrtPriceMath` functions, with verified axioms (specified behavior).
- **SqrtPriceMath.spec**: Test rules for `SqrtPriceMath`, including the axioms in `SqrtPriceMathRealSummary.spec`.
- **StateLibraryTest.spec**: Equivalence check between stroage access in PoolManager and the `StateLibraryTest` functions.
- **SwapHookTest.spec**: Includes a CVL version of the fuzz rule `test/customAccounting.t.sol/test_fuzz_swap_beforeSwap_returnsDeltaSpecified`.
- **SwapMathTest.spec**: Testing rules for the `SwapMath` library.
- **SwapStepDetSummary.spec**: Deterministic summarization for the `SwapMath` functions, without any axioms (unspecified behavior).
- **SwapStepSummary.spec**: Deterministic summarization for the `SwapMath` functions, with verified axioms (specified behavior).
- **TickBitmapTest.spec**: Test rules for the `TickBitmap` library.
- **TickMathSummary.spec**: Summarization of the `TickMath` library.
- **UnsafeMathSummary.spec**: Summarization of the `UnsafeMath` math library.
