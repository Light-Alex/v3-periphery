// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

// V3 核心库 - 低 Gas 安全数学运算
import '@uniswap/v3-core/contracts/libraries/LowGasSafeMath.sol';
// V2 核心接口 - V2 交易对接口
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

// 本项目接口 - NFT 位置管理器接口
import './interfaces/INonfungiblePositionManager.sol';

// 库文件 - 转账辅助工具
import './libraries/TransferHelper.sol';

// 本项目接口 - V3 迁移器接口
import './interfaces/IV3Migrator.sol';
// 基础合约 - 不可变状态
import './base/PeripheryImmutableState.sol';
// 基础合约 - 多重调用
import './base/Multicall.sol';
// 基础合约 - 自许可
import './base/SelfPermit.sol';
// 外部接口 - WETH9 接口
import './interfaces/external/IWETH9.sol';
// 基础合约 - 池初始化
import './base/PoolInitializer.sol';

/// @title Uniswap V3 Migrator
/// @notice_zh Uniswap V3 迁移器 - 将 V2 流动性迁移到 V3
/// @dev_zh 此合约帮助用户将 Uniswap V2 的流动性位置迁移到 Uniswap V3
/// @dev_zh 支持部分迁移（按百分比），并自动处理代币退款
contract V3Migrator is IV3Migrator, PeripheryImmutableState, PoolInitializer, Multicall, SelfPermit {
    // 使用低 Gas 安全数学库扩展 uint256 类型
    using LowGasSafeMath for uint256;

    /// @dev_zh NFT 位置管理器合约地址（不可变）
    address public immutable nonfungiblePositionManager;

    /// @notice_zh 构造函数 - 初始化合约参数
    /// @param _factory Uniswap V3 Factory 地址
    /// @param _WETH9 WETH9 合约地址
    /// @param _nonfungiblePositionManager NFT 位置管理器合约地址
    constructor(
        address _factory,
        address _WETH9,
        address _nonfungiblePositionManager
    ) PeripheryImmutableState(_factory, _WETH9) {
        nonfungiblePositionManager = _nonfungiblePositionManager;
    }

    /// @notice_zh 接收 ETH - 只接受来自 WETH9 的 ETH
    /// @dev_zh 此函数用于接收 WETH 解包后的 ETH
    receive() external payable {
        require(msg.sender == WETH9, 'Not WETH9');
    }

    /// @inheritdoc IV3Migrator
    /// @notice_zh 将 Uniswap V2 流动性迁移到 Uniswap V3
    /// @dev_zh 此函数执行完整的迁移流程：移除 V2 流动性 → 创建 V3 流动性 → 退款剩余代币
    /// @param params 迁移参数，包含：
    ///   - pair: V2 交易对地址
    ///   - liquidityToMigrate: 要迁移的 V2 流动性数量
    ///   - percentageToMigrate: 迁移百分比（0-100）
    ///   - token0/token1: 代币地址
    ///   - fee: V3 池子费用等级
    ///   - tickLower/tickUpper: V3 价格区间
    ///   - amount0Min/amount1Min: 最小接收数量（滑点保护）
    ///   - recipient: V3 NFT 接收地址
    ///   - deadline: 交易截止时间
    ///   - refundAsETH: 是否将剩余的 WETH 作为 ETH 退款
    function migrate(MigrateParams calldata params) external override {
        // @dev_zh 检查迁移百分比是否有效
        require(params.percentageToMigrate > 0, 'Percentage too small');
        require(params.percentageToMigrate <= 100, 'Percentage too large');

        // burn v2 liquidity to this address
        // @dev_zh 将 V2 流动性代币从用户转移到交易对，然后移除流动性到此合约
        IUniswapV2Pair(params.pair).transferFrom(msg.sender, params.pair, params.liquidityToMigrate);
        (uint256 amount0V2, uint256 amount1V2) = IUniswapV2Pair(params.pair).burn(address(this));

        // calculate the amounts to migrate to v3
        // @dev_zh 根据百分比计算要迁移到 V3 的代币数量
        uint256 amount0V2ToMigrate = amount0V2.mul(params.percentageToMigrate) / 100;
        uint256 amount1V2ToMigrate = amount1V2.mul(params.percentageToMigrate) / 100;

        // approve the position manager up to the maximum token amounts
        // @dev_zh 批准 NFT 位置管理器使用代币
        TransferHelper.safeApprove(params.token0, nonfungiblePositionManager, amount0V2ToMigrate);
        TransferHelper.safeApprove(params.token1, nonfungiblePositionManager, amount1V2ToMigrate);

        // mint v3 position
        // @dev_zh 在 V3 中创建新的流动性位置
        (, , uint256 amount0V3, uint256 amount1V3) =
            INonfungiblePositionManager(nonfungiblePositionManager).mint(
                INonfungiblePositionManager.MintParams({
                    token0: params.token0,
                    token1: params.token1,
                    fee: params.fee,
                    tickLower: params.tickLower,
                    tickUpper: params.tickUpper,
                    amount0Desired: amount0V2ToMigrate,
                    amount1Desired: amount1V2ToMigrate,
                    amount0Min: params.amount0Min,
                    amount1Min: params.amount1Min,
                    recipient: params.recipient,
                    deadline: params.deadline
                })
            );

        // if necessary, clear allowance and refund dust
        // @dev_zh 如果有剩余代币，清除授权并退款
        if (amount0V3 < amount0V2) {
            // @dev_zh 如果 V3 使用的代币少于批准数量，清除授权
            if (amount0V3 < amount0V2ToMigrate) {
                TransferHelper.safeApprove(params.token0, nonfungiblePositionManager, 0);
            }

            // @dev_zh 计算退款金额
            uint256 refund0 = amount0V2 - amount0V3;
            // @dev_zh 如果是 WETH 且要求退款为 ETH，则解包并发送 ETH
            if (params.refundAsETH && params.token0 == WETH9) {
                IWETH9(WETH9).withdraw(refund0);
                TransferHelper.safeTransferETH(msg.sender, refund0);
            } else {
                // @dev_zh 否则直接退还代币
                TransferHelper.safeTransfer(params.token0, msg.sender, refund0);
            }
        }

        // @dev_zh 对 token1 执行相同的退款逻辑
        if (amount1V3 < amount1V2) {
            if (amount1V3 < amount1V2ToMigrate) {
                TransferHelper.safeApprove(params.token1, nonfungiblePositionManager, 0);
            }

            uint256 refund1 = amount1V2 - amount1V3;
            if (params.refundAsETH && params.token1 == WETH9) {
                IWETH9(WETH9).withdraw(refund1);
                TransferHelper.safeTransferETH(msg.sender, refund1);
            } else {
                TransferHelper.safeTransfer(params.token1, msg.sender, refund1);
            }
        }
    }
}
