// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

// V3 核心接口 - 工厂合约接口
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
// V3 核心接口 - 铸造回调接口
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol';
// V3 核心库 - Tick 数学运算
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';

// 本项目库 - 池地址计算
import '../libraries/PoolAddress.sol';
// 本项目库 - 回调验证
import '../libraries/CallbackValidation.sol';
// 本项目库 - 流动性数量计算
import '../libraries/LiquidityAmounts.sol';

// 基础合约 - 支付功能
import './PeripheryPayments.sol';
// 基础合约 - 不可变状态
import './PeripheryImmutableState.sol';

/// @title Liquidity management functions
/// @notice Internal functions for safely managing liquidity in Uniswap V3
/// @notice_zh 流动性管理功能 - 用于安全管理 Uniswap V3 流动性的内部函数
/// @dev_zh 此抽象合约提供了添加流动性的核心功能，实现了铸造回调接口
abstract contract LiquidityManagement is IUniswapV3MintCallback, PeripheryImmutableState, PeripheryPayments {
    /// @dev_zh MintCallbackData 结构体 - 铸造回调数据
    /// @dev_zh 当池子调用 mint 时，会将此数据传递给回调函数
    struct MintCallbackData {
        PoolAddress.PoolKey poolKey;  // @dev_zh 池子密钥（包含代币地址和费用）
        address payer;  // @dev_zh 支付代币的地址（通常是用户地址）
    }

    /// @inheritdoc IUniswapV3MintCallback
    /// @notice_zh Uniswap V3 铸造回调函数
    /// @dev_zh 当调用 pool.mint() 时，池子会调用此回调函数来获取代币
    /// @param amount0Owed 需要支付的 token0 数量
    /// @param amount1Owed 需要支付的 token1 数量
    /// @param data 编码的回调数据（MintCallbackData）
    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external override {
        // @dev_zh 解码回调数据
        MintCallbackData memory decoded = abi.decode(data, (MintCallbackData));
        // @dev_zh 验证调用者是否为预期的池子（安全检查）
        CallbackValidation.verifyCallback(factory, decoded.poolKey);

        // @dev_zh 如果需要支付 token0，从 payer 转账到池子
        if (amount0Owed > 0) pay(decoded.poolKey.token0, decoded.payer, msg.sender, amount0Owed);
        // @dev_zh 如果需要支付 token1，从 payer 转账到池子
        if (amount1Owed > 0) pay(decoded.poolKey.token1, decoded.payer, msg.sender, amount1Owed);
    }

    /// @dev_zh AddLiquidityParams 结构体 - 添加流动性参数
    /// @dev_zh 此结构体包含了添加流动性所需的所有参数
    struct AddLiquidityParams {
        address token0;  // @dev_zh 池子的第一个代币地址
        address token1;  // @dev_zh 池子的第二个代币地址
        uint24 fee;  // @dev_zh 池子的费用等级（500, 3000, 10000）
        address recipient;  // @dev_zh 接收流动性的地址
        int24 tickLower;  // @dev_zh 价格区间的下限 tick
        int24 tickUpper;  // @dev_zh 价格区间的上限 tick
        uint256 amount0Desired;  // @dev_zh 期望添加的 token0 数量
        uint256 amount1Desired;  // @dev_zh 期望添加的 token1 数量
        uint256 amount0Min;  // @dev_zh 最少添加的 token0 数量（滑点保护）
        uint256 amount1Min;  // @dev_zh 最少添加的 token1 数量（滑点保护）
    }

    /// @notice Add liquidity to an initialized pool
    /// @notice_zh 向已初始化的池子添加流动性
    /// @param params 添加流动性参数
    /// @return liquidity 实际添加的流动性数量
    /// @return amount0 实际使用的 token0 数量
    /// @return amount1 实际使用的 token1 数量
    /// @return pool 池子合约地址
    function addLiquidity(AddLiquidityParams memory params)
        internal
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1,
            IUniswapV3Pool pool
        )
    {
        // @dev_zh 构建池子密钥
        PoolAddress.PoolKey memory poolKey =
            PoolAddress.PoolKey({token0: params.token0, token1: params.token1, fee: params.fee});

        // @dev_zh 计算池子合约地址并获取池子实例
        pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey));

        // compute the liquidity amount
        // @dev_zh 计算流动性数量（根据当前价格和价格区间）
        {
            // @dev_zh 获取池子当前状态（sqrtPriceX96 为当前价格的平方根）
            (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
            // @dev_zh 计算价格区间下限的平方根
            uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(params.tickLower);
            // @dev_zh 计算价格区间上限的平方根
            uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(params.tickUpper);

            // @dev_zh 根据期望的代币数量和价格区间，计算可以添加的流动性数量
            liquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96,
                sqrtRatioAX96,
                sqrtRatioBX96,
                params.amount0Desired,
                params.amount1Desired
            );
        }

        // @dev_zh 调用池子的 mint 函数添加流动性
        // @dev_zh 这会触发 uniswapV3MintCallback 回调函数来获取代币
        (amount0, amount1) = pool.mint(
            params.recipient,
            params.tickLower,
            params.tickUpper,
            liquidity,
            abi.encode(MintCallbackData({poolKey: poolKey, payer: msg.sender}))
        );

        // @dev_zh 滑点检查：确保实际使用的代币数量满足最小值要求
        require(amount0 >= params.amount0Min && amount1 >= params.amount1Min, 'Price slippage check');
    }
}
