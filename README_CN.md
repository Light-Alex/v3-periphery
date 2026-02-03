# Uniswap V3 Periphery

[![Tests](https://github.com/Uniswap/uniswap-v3-periphery/workflows/Tests/badge.svg)](https://github.com/Uniswap/uniswap-v3-periphery/actions?query=workflow%3ATests)
[![Lint](https://github.com/Uniswap/uniswap-v3-periphery/workflows/Lint/badge.svg)](https://github.com/Uniswap/uniswap-v3-periphery/actions?query=workflow%3ALint)

本仓库包含 Uniswap V3 协议的周边智能合约。
如需查看底层核心合约，请访问 [uniswap-v3-core](https://github.com/Uniswap/uniswap-v3-core) 仓库。

## 目录

- [项目简介](#项目简介)
- [主要功能模块](#主要功能模块)
- [基础组件](#基础组件)
- [核心库文件](#核心库文件)
- [技术栈](#技术栈)
- [安装和使用](#安装和使用)
- [开发命令](#开发命令)
- [依赖项](#依赖项)
- [相关链接](#相关链接)

---

## 项目简介

**Uniswap V3 Periphery** 是 Uniswap V3 协议的周边合约库，提供了与 Uniswap V3 核心协议交互的高级功能。

- **版本**: 1.4.4
- **许可证**: GPL-2.0-or-later
- **官网**: https://uniswap.org
- **GitHub**: https://github.com/Uniswap/uniswap-v3-periphery

### 核心功能

- **代币交换路由**: 执行单跳和多跳代币交换
- **NFT 流动性位置管理**: 将流动性位置包装为 ERC721 代币
- **价格预言机**: 提供池子价格信息用于交易决策
- **批量操作**: 通过 Multicall 一次性执行多个操作
- **费用收集**: 流动性提供者可以收集交易费用
- **V2 到 V3 迁移**: 支持从 Uniswap V2 迁移流动性

---

## 主要功能模块

### 1. 代币交换 (SwapRouter)

**SwapRouter** 是执行代币交换的主要路由器合约。

#### 功能特性

- **精确输入交换** (`exactInput`/`exactInputSingle`): 用精确的输入量交换尽可能多的输出代币
- **精确输出交换** (`exactOutput`/`exactOutputSingle`): 用尽可能少的输入量交换精确的输出代币
- **单跳交换**: 直接在两个代币之间交换
- **多跳交换**: 通过多个池子进行代币交换（例如 USDC → WETH → DAI）
- **滑点保护**: 通过设置最小/最大输出量保护免受滑点影响
- **截止时间检查**: 交易必须在指定时间内完成

#### 使用示例

```solidity
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';

contract MyContract {
    ISwapRouter router;

    constructor(address _router) {
        router = ISwapRouter(_router);
    }

    function swapTokens() external {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
            tokenOut: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH
            fee: 3000, // 0.3% 费用等级
            recipient: msg.sender,
            deadline: block.timestamp + 300,
            amountIn: 1000000, // 1 USDC (6 decimals)
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        router.exactInputSingle(params);
    }
}
```

### 2. NFT 流动性位置管理 (NonfungiblePositionManager)

**NonfungiblePositionManager** 将 Uniswap V3 流动性位置包装为 ERC721 非同质化代币，使流动性位置可以被转移、授权和管理。

#### 功能特性

| 功能 | 方法 | 说明 |
|------|------|------|
| 创建流动性位置 | `mint` | 创建新的流动性位置并铸造 NFT |
| 增加流动性 | `increaseLiquidity` | 为现有位置增加流动性 |
| 减少流动性 | `decreaseLiquidity` | 从位置中移除流动性 |
| 收集费用 | `collect` | 收集位置产生的交易费用 |
| 销毁 NFT | `burn` | 销毁 NFT（需要流动性为 0 且已收集所有费用） |

#### 位置参数说明

创建流动性位置时需要指定：

- `token0` / `token1`: 交易对代币地址
- `fee`: 池子费用等级（500=0.05%, 3000=0.3%, 10000=1%）
- `tickLower` / `tickUpper`: 价格区间范围
- `amount0Desired` / `amount1Desired`: 期望存入的代币数量

#### 使用示例

```solidity
import '@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol';

contract LiquidityProvider {
    INonfungiblePositionManager positionManager;

    constructor(address _positionManager) {
        positionManager = INonfungiblePositionManager(_positionManager);
    }

    function createPosition() external payable {
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            token1: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            fee: 3000,
            tickLower: -60750,  // 约等于 0.0005 的价格下限
            tickUpper: -60650,  // 约等于 0.0005 的价格上限
            amount0Desired: 1000000,
            amount1Desired: 1 ether,
            amount0Min: 0,
            amount1Min: 0,
            recipient: msg.sender,
            deadline: block.timestamp + 300
        });

        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) =
            positionManager.mint(params);
    }
}
```

### 3. V2 到 V3 迁移 (V3Migrator)

**V3Migrator** 允许将 Uniswap V2 的流动性迁移到 V3。

#### 功能特性

- 从 V2 池子移除流动性
- 在 V3 池子中创建新的流动性位置
- 支持指定 V3 位置的价格区间
- 自动创建 V3 池子（如果不存在）

---

## 基础组件

### Multicall

允许在一个交易中执行多个函数调用，减少交易成本并提高效率。

```solidity
// 批量调用示例
bytes[] memory data = new bytes[](2);
data[0] = abi.encodeWithSelector(ISwapRouter.exactInput.selector, params1);
data[1] = abi.encodeWithSelector(ISwapRouter.exactInput.selector, params2);
router.multicall(data);
```

### PeripheryPayments

处理 WETH 支付和代币兑换，自动处理 ETH 和 WETH 之间的转换。

### PeripheryValidation

提供交易验证功能，包括截止时间检查，确保交易在指定时间内执行。

### LiquidityManagement

管理流动性操作的基础合约，提供添加、移除和修改流动性的核心功能。

### PoolInitializer

负责初始化新的 V3 池子，设置初始价格。

### ERC721Permit

实现 ERC721 的 Permit 机制，允许无 gas 费的授权操作（通过签名）。

### SelfPermit

允许合约自行处理代币授权，支持多种代币标准的 Permit 功能。

---

## 核心库文件

### Path.sol

编码和解码代币交换路径。

```typescript
// 路径格式: tokenA + fee + tokenB + fee + tokenC
// 例如: USDC → WETH → DAI
const path = ethers.utils.solidityPack(
  ['address', 'uint24', 'address', 'uint24', 'address'],
  [USDC, 3000, WETH, 3000, DAI]
);
```

### LiquidityAmounts.sol

计算流动性数量和代币数量，用于确定添加或移除流动性时需要的代币数量。

### PoolAddress.sol

根据工厂地址和代币对计算池子地址。

### NFTDescriptor.sol

生成 NFT 的元数据和 SVG 图像，使每个流动性位置 NFT 都有独特的视觉表现。

### OracleLibrary.sol

价格预言机功能，提供：

- 查询历史价格
- 计算价格变化趋势
- 获取价格区间信息

---

## 技术栈

- **Solidity**: 0.7.6
- **开发框架**: Hardhat
- **语言**: TypeScript
- **区块链库**: Ethers.js v5
- **测试框架**: Mocha + Chai

---

## 安装和使用

### 安装

```bash
npm install @uniswap/v3-periphery
```

### 本地部署

要部署此代码到本地测试网，应安装 npm 包 `@uniswap/v3-periphery` 并导入位于 `@uniswap/v3-periphery/artifacts/contracts/*/*.json` 的字节码。

```typescript
import {
  abi as SWAP_ROUTER_ABI,
  bytecode as SWAP_ROUTER_BYTECODE,
} from '@uniswap/v3-periphery/artifacts/contracts/SwapRouter.sol/SwapRouter.json'

// 部署字节码
const factory = await ethers.getContractFactory(SWAP_ROUTER_ABI, SWAP_ROUTER_BYTECODE);
const router = await factory.deploy(factoryAddress, weth9Address);
```

这将确保你测试的是与主网和公共测试网相同的字节码，所有 Uniswap 代码都将与你的本地部署正确互操作。

### 在 Solidity 中使用接口

Uniswap v3 周边接口可通过 npm 包 `@uniswap/v3-periphery` 导入到 Solidity 智能合约中：

```solidity
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';

contract MyContract {
  ISwapRouter router;

  constructor(address _router) {
    router = ISwapRouter(_router);
  }

  function doSomethingWithSwapRouter() external {
    // 使用 router 进行代币交换
    // router.exactInput(...);
  }
}
```

### 可用的接口

- `ISwapRouter.sol` - 交换路由器接口
- `INonfungiblePositionManager.sol` - NFT 位置管理器接口
- `IPeripheryPayments.sol` - 支付接口
- `INonfungibleTokenPositionDescriptor.sol` - NFT 描述符接口

---

## 开发命令

```bash
# 编译合约
npm run compile

# 运行测试
npm run test

# 代码格式化
npm run format

# 代码检查
npm run lint
```

---

## 依赖项

### 核心依赖

- **@uniswap/v3-core**: Uniswap V3 核心合约（Pool、Factory 等）
- **@uniswap/v2-core**: Uniswap V2 核心合约（用于迁移功能）
- **@openzeppelin/contracts**: 标准合约库（ERC20、ERC721 等）
- **@uniswap/lib**: Uniswap 工具库

### 开发依赖

- **hardhat**: 以太坊开发环境
- **ethers.js**: 以太坊交互库
- **@typechain/ethers-v5**: 类型安全的合约交互
- **prettier**: 代码格式化工具
- **solhint**: Solidity 代码检查工具

---

## 相关链接

- [Uniswap V3 Core](https://github.com/Uniswap/uniswap-v3-core) - 核心合约仓库
- [Uniswap V3 SDK](https://github.com/Uniswap/v3-sdk) - JavaScript/TypeScript SDK
- [Uniswap 官方文档](https://docs.uniswap.org/)
- [Uniswap V3 白皮书](https://uniswap.org/whitepaper-v3.pdf)

---

## 费用等级

Uniswap V3 池子有不同的费用等级：

| 费用等级 | 百分比 | 适用场景 |
|---------|--------|---------|
| 500 | 0.05% | 稳定币交易对 |
| 3000 | 0.3% | 标准交易对 |
| 10000 | 1% | 波动较大的代币 |

---

## 安全与漏洞赏金

本仓库参与 Uniswap V3 漏洞赏金计划，详细条款请查看 [bug-bounty.md](./bug-bounty.md)。

---

## 项目结构

```
v3-periphery/
├── contracts/                  # 主要合约代码
│   ├── base/                   # 基础合约组件
│   │   ├── Multicall.sol
│   │   ├── PeripheryPayments.sol
│   │   ├── PeripheryValidation.sol
│   │   └── ...
│   ├── interfaces/             # 接口定义
│   │   ├── ISwapRouter.sol
│   │   ├── INonfungiblePositionManager.sol
│   │   └── ...
│   ├── libraries/              # 核心库文件
│   │   ├── Path.sol
│   │   ├── LiquidityAmounts.sol
│   │   ├── PoolAddress.sol
│   │   └── ...
│   ├── SwapRouter.sol          # 交换路由器
│   ├── NonfungiblePositionManager.sol  # NFT 位置管理器
│   └── V3Migrator.sol          # V2 到 V3 迁移工具
├── test/                       # 测试文件
├── scripts/                    # 部署脚本
└── artifacts/                  # 编译后的合约字节码
```

---

## 许可证

本项目采用 GPL-2.0-or-later 许可证。
