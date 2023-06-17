# Uniswap v4 核心

[![Lint](https://github.com/Uniswap/v4-core/actions/workflows/lint.yml/badge.svg)](https://github.com/Uniswap/v4-core/actions/workflows/lint.yml)
[![Tests](https://github.com/Uniswap/v4-core/actions/workflows/tests.yml/badge.svg)](https://github.com/Uniswap/v4-core/actions/workflows/tests.yml)

> 中文翻译由 [WTF Academy](https://twitter.com/WTFAcademy_) 贡献

Uniswap v4 是一个提供可扩展和可定制化交易池的新型自动化做市商协议。`v4-core` 承载了创建交易池和执行交易池操作（如交换和提供流动性）的核心逻辑。

这个仓库中的合约处于早期阶段 - 我们现在发布草案代码，以便让 v4 在公开环境中构建，接受开放反馈和有意义的社区贡献。我们预计这将是一个持续几个月的过程，并且我们非常感谢任何形式的贡献，无论大小。

## 贡献

如果您有兴趣进行贡献，请参阅我们的[贡献指南](./CONTRIBUTING.md)！

## 白皮书

关于 Uniswap v4 核心的更详细描述可以在 [Uniswap v4 核心白皮书草案](./whitepaper-v4-draft-zh.pdf) 中找到。

## 架构

`v4-core` 使用单例式架构，所有交易池状态都由 `PoolManager.sol` 合约管理。通过在合约上获取锁并实现 `lockAcquired` 回调，可以进行交易池操作的执行，包括以下操作：

- `swap`（交换）
- `modifyPosition`（修改仓位）
- `donate`（捐赠）
- `take`（获取）
- `settle`（结算）
- `mint`（铸造）

在锁定（lock）的持续时间内，合约只追踪欠交易池的净余额（负值）或欠用户的净余额（正值），在锁定状态的 `delta` 字段中保存。用户可以在交易池上执行任意数量的操作，只要在锁定结束时累积的 delta 为 0。这种锁定和调用的架构为调用者基于核心代码开发时提供了最大的灵活性。

此外，交易池可以被钩子合约（Hook）初始化，该钩子合约可以在交易池操作的生命周期中实现以下回调函数：

- {before,after}Initialize
- {before,after}ModifyPosition
- {before,after}Swap
- {before,after}Donate

钩子还可以选择在交换或提取流动性时指定费用。与上述操作类似，费用是使用回调函数实现的。

费用或回调逻辑可以根据其实现进行更新。但是，在交易池初始化后，哪种类型的回调被执行无法被更改，这包括包括有无费用和费用类型（静态或动态费用）。

## 仓库结构

所有合约都保存在 `v4-core/contracts` 文件夹中。

请注意，测试使用的辅助合约保存在合约文件夹内的 `v4-core/contracts/test` 子文件夹中。任何新的测试辅助合约都应添加到此处，但所有的铸造测试都在 `v4-core/test/foundry-tests` 文件夹中。

```markdown
contracts/
----interfaces/
    | IPoolManager.sol
    | ...
----libraries/
    | Position.sol
    | Pool.sol
    | ...
----test
...
PoolManager.sol
test/
----foundry-tests/
```

## 本地部署和使用

要使用这些合约并部署到本地测试网络，您可以使用 Forge 在您的仓库中安装代码：

```markdown
forge install https://github.com/Uniswap/v4-core
```

要与合约集成，可以使用提供的接口：

```solidity
import {IPoolManager} from 'v4-core/contracts/interfaces/IPoolManager.sol';
import {ILockCallback} from 'v4-core/contracts/interfaces/callback/ILockCallback.sol';

contract MyContract is ILockCallback {
    IPoolManager poolManager;

    function doSomethingWithPools() {
        // 此函数将调用下面的 `lockAcquired`
        poolManager.lock(...);
    }

    function lockAcquired(uint256 id, bytes calldata data) external returns (bytes memory) {
        // 执行交易池操作
        poolManager.swap(...)
    }
}
```

## 许可证

Uniswap V4 Core 的主要许可证是 Business Source License 1.1 (`BUSL-1.1`)，详见 [LICENSE](https://github.com/Uniswap/v4-core/blob/main/LICENSE)。以下是例外情况：

- [Interfaces](./contracts/interfaces) 使用了通用公共许可证
- 一些 [libraries](./contracts/libraries) 和 [types](./contracts/types/) 使用了通用公共许可证
- [FullMath.sol](./contracts/libraries/FullMath.sol) 使用了 MIT 许可证

每个文件都说明了它们的许可证类型。