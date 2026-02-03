// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

// V3 核心库 - 完整数学运算（避免溢出）
import '@uniswap/v3-core/contracts/libraries/FullMath.sol';
// V3 核心库 - 定点数运算（Q96 格式）
import '@uniswap/v3-core/contracts/libraries/FixedPoint96.sol';

/// @title Liquidity amount functions
/// @notice Provides functions for computing liquidity amounts from token amounts and prices
/// @notice_zh 流动性数量计算库 - 提供根据代币数量和价格计算流动性数量的函数
/// @dev_zh 此库包含了流动性与代币数量之间相互转换的所有计算函数
/// @dev_zh 这是 Uniswap V3 流动性管理的核心数学库
library LiquidityAmounts {
    /// @notice Downcasts uint256 to uint128
    /// @notice_zh 将 uint256 转换为 uint128
    /// @param x The uint258 to be downcasted
    /// @param_zh x 要转换的 uint256 值
    /// @return y The passed value, downcasted to uint128
    /// @return_zh y 转换后的 uint128 值（如果溢出则抛出错误）
    function toUint128(uint256 x) private pure returns (uint128 y) {
        require((y = uint128(x)) == x);
    }

    /// @notice Computes the amount of liquidity received for a given amount of token0 and price range
    /// @dev Calculates amount0 * (sqrt(upper) * sqrt(lower)) / (sqrt(upper) - sqrt(lower))
    /// @notice_zh 计算给定 token0 数量和价格区间可以获得的流动性数量
    /// @dev_zh 计算公式：amount0 * (sqrt(upper) * sqrt(lower)) / (sqrt(upper) - sqrt(lower))
    /// @dev_zh 此函数用于当当前价格低于区间下限时，计算只需 token0 时的流动性
    /// @param sqrtRatioAX96 A sqrt price representing the first tick boundary
    /// @param_zh sqrtRatioAX96 第一个 tick 边界的平方根价格（X96 格式）
    /// @param sqrtRatioBX96 A sqrt price representing the second tick boundary
    /// @param_zh sqrtRatioBX96 第二个 tick 边界的平方根价格（X96 格式）
    /// @param amount0 The amount0 being sent in
    /// @param_zh amount0 存入的 token0 数量
    /// @return liquidity The amount of returned liquidity
    /// @return_zh liquidity 计算得到的流动性数量
    function getLiquidityForAmount0(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0
    ) internal pure returns (uint128 liquidity) {
        // @dev_zh 确保 sqrtRatioAX96 是较小的价格
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        // @dev_zh 计算 sqrt(upper) * sqrt(lower) / Q96
        uint256 intermediate = FullMath.mulDiv(sqrtRatioAX96, sqrtRatioBX96, FixedPoint96.Q96);
        // @dev_zh 计算最终流动性：amount0 * intermediate / (sqrt(upper) - sqrt(lower))
        return toUint128(FullMath.mulDiv(amount0, intermediate, sqrtRatioBX96 - sqrtRatioAX96));
    }

    /// @notice Computes the amount of liquidity received for a given amount of token1 and price range
    /// @dev Calculates amount1 / (sqrt(upper) - sqrt(lower)).
    /// @notice_zh 计算给定 token1 数量和价格区间可以获得的流动性数量
    /// @dev_zh 计算公式：amount1 / (sqrt(upper) - sqrt(lower))
    /// @dev_zh 此函数用于当当前价格高于区间上限时，计算只需 token1 时的流动性
    /// @param sqrtRatioAX96 A sqrt price representing the first tick boundary
    /// @param_zh sqrtRatioAX96 第一个 tick 边界的平方根价格（X96 格式）
    /// @param sqrtRatioBX96 A sqrt price representing the second tick boundary
    /// @param_zh sqrtRatioBX96 第二个 tick 边界的平方根价格（X96 格式）
    /// @param amount1 The amount1 being sent in
    /// @param_zh amount1 存入的 token1 数量
    /// @return liquidity The amount of returned liquidity
    /// @return_zh liquidity 计算得到的流动性数量
    function getLiquidityForAmount1(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        // @dev_zh 确保 sqrtRatioAX96 是较小的价格
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        // @dev_zh 计算流动性：amount1 * Q96 / (sqrt(upper) - sqrt(lower))
        return toUint128(FullMath.mulDiv(amount1, FixedPoint96.Q96, sqrtRatioBX96 - sqrtRatioAX96));
    }

    /// @notice Computes the maximum amount of liquidity received for a given amount of token0, token1, the current
    /// pool prices and the prices at the tick boundaries
    /// @notice_zh 计算给定 token0、token1 数量、当前池价格和 tick 边界价格时可以获得的最大流动性
    /// @dev_zh 这是流动性计算的核心函数，根据当前价格相对于区间的位置使用不同的计算方式
    /// @dev_zh 有三种情况：
    /// @dev_zh 1. 当前价格 ≤ 区间下限：只需要 token0
    /// @dev_zh 2. 区间下限 < 当前价格 < 区间上限：同时需要 token0 和 token1，取较小值
    /// @dev_zh 3. 当前价格 ≥ 区间上限：只需要 token1
    /// @param sqrtRatioX96 A sqrt price representing the current pool prices
    /// @param_zh sqrtRatioX96 当前池价格的平方根（X96 格式）
    /// @param sqrtRatioAX96 A sqrt price representing the first tick boundary
    /// @param_zh sqrtRatioAX96 第一个 tick 边界的平方根价格（X96 格式）
    /// @param sqrtRatioBX96 A sqrt price representing the second tick boundary
    /// @param_zh sqrtRatioBX96 第二个 tick 边界的平方根价格（X96 格式）
    /// @param amount0 The amount of token0 being sent in
    /// @param_zh amount0 存入的 token0 数量
    /// @param amount1 The amount of token1 being sent in
    /// @param_zh amount1 存入的 token1 数量
    /// @return liquidity The maximum amount of liquidity received
    /// @return_zh liquidity 获得的最大流动性数量
    function getLiquidityForAmounts(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        // @dev_zh 确保 sqrtRatioAX96 ≤ sqrtRatioBX96
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        if (sqrtRatioX96 <= sqrtRatioAX96) {
            // @dev_zh 情况1：当前价格低于或等于区间下限，只需 token0
            liquidity = getLiquidityForAmount0(sqrtRatioAX96, sqrtRatioBX96, amount0);
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            // @dev_zh 情况2：当前价格在区间内，需要同时计算 token0 和 token1 的流动性，取较小值
            uint128 liquidity0 = getLiquidityForAmount0(sqrtRatioX96, sqrtRatioBX96, amount0);
            uint128 liquidity1 = getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioX96, amount1);

            // @dev_zh 取较小值确保两种代币都足够
            liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        } else {
            // @dev_zh 情况3：当前价格高于或等于区间上限，只需 token1
            liquidity = getLiquidityForAmount1(sqrtRatioAX96, sqrtRatioBX96, amount1);
        }
    }

    /// @notice Computes the amount of token0 for a given amount of liquidity and a price range
    /// @notice_zh 计算给定流动性数量和价格区间需要的 token0 数量
    /// @dev_zh 此函数用于从流动性反推需要的代币数量
    /// @param sqrtRatioAX96 A sqrt price representing the first tick boundary
    /// @param_zh sqrtRatioAX96 第一个 tick 边界的平方根价格（X96 格式）
    /// @param sqrtRatioBX96 A sqrt price representing the second tick boundary
    /// @param_zh sqrtRatioBX96 第二个 tick 边界的平方根价格（X96 格式）
    /// @param liquidity The liquidity being valued
    /// @param_zh liquidity 要估值的流动性数量
    /// @return amount0 The amount of token0
    /// @return_zh amount0 需要的 token0 数量
    function getAmount0ForLiquidity(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0) {
        // @dev_zh 确保 sqrtRatioAX96 ≤ sqrtRatioBX96
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        // @dev_zh 计算 token0 数量：liquidity * (sqrt(upper) - sqrt(lower)) / sqrt(upper) / sqrt(lower)
        return
            FullMath.mulDiv(
                uint256(liquidity) << FixedPoint96.RESOLUTION,
                sqrtRatioBX96 - sqrtRatioAX96,
                sqrtRatioBX96
            ) / sqrtRatioAX96;
    }

    /// @notice Computes the amount of token1 for a given amount of liquidity and a price range
    /// @notice_zh 计算给定流动性数量和价格区间需要的 token1 数量
    /// @dev_zh 此函数用于从流动性反推需要的代币数量
    /// @param sqrtRatioAX96 A sqrt price representing the first tick boundary
    /// @param_zh sqrtRatioAX96 第一个 tick 边界的平方根价格（X96 格式）
    /// @param sqrtRatioBX96 A sqrt price representing the second tick boundary
    /// @param_zh sqrtRatioBX96 第二个 tick 边界的平方根价格（X96 格式）
    /// @param liquidity The liquidity being valued
    /// @param_zh liquidity 要估值的流动性数量
    /// @return amount1 The amount of token1
    /// @return_zh amount1 需要的 token1 数量
    function getAmount1ForLiquidity(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount1) {
        // @dev_zh 确保 sqrtRatioAX96 ≤ sqrtRatioBX96
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        // @dev_zh 计算 token1 数量：liquidity * (sqrt(upper) - sqrt(lower)) / Q96
        return FullMath.mulDiv(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96);
    }

    /// @notice Computes the token0 and token1 value for a given amount of liquidity, the current
    /// pool prices and the prices at the tick boundaries
    /// @notice_zh 计算给定流动性数量、当前池价格和 tick 边界价格时的 token0 和 token1 数量
    /// @dev_zh 这是 getAmount0ForLiquidity 和 getAmount1ForLiquidity 的组合函数
    /// @dev_zh 根据当前价格相对于区间的位置返回不同的结果
    /// @param sqrtRatioX96 A sqrt price representing the current pool prices
    /// @param_zh sqrtRatioX96 当前池价格的平方根（X96 格式）
    /// @param sqrtRatioAX96 A sqrt price representing the first tick boundary
    /// @param_zh sqrtRatioAX96 第一个 tick 边界的平方根价格（X96 格式）
    /// @param sqrtRatioBX96 A sqrt price representing the second tick boundary
    /// @param_zh sqrtRatioBX96 第二个 tick 边界的平方根价格（X96 格式）
    /// @param liquidity The liquidity being valued
    /// @param_zh liquidity 要估值的流动性数量
    /// @return amount0 The amount of token0
    /// @return_zh amount0 token0 的数量
    /// @return amount1 The amount of token1
    /// @return_zh amount1 token1 的数量
    function getAmountsForLiquidity(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        // @dev_zh 确保 sqrtRatioAX96 ≤ sqrtRatioBX96
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        if (sqrtRatioX96 <= sqrtRatioAX96) {
            // @dev_zh 当前价格低于区间下限：只需要 token0
            amount0 = getAmount0ForLiquidity(sqrtRatioAX96, sqrtRatioBX96, liquidity);
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            // @dev_zh 当前价格在区间内：需要同时计算 token0 和 token1
            amount0 = getAmount0ForLiquidity(sqrtRatioX96, sqrtRatioBX96, liquidity);
            amount1 = getAmount1ForLiquidity(sqrtRatioAX96, sqrtRatioX96, liquidity);
        } else {
            // @dev_zh 当前价格高于区间上限：只需要 token1
            amount1 = getAmount1ForLiquidity(sqrtRatioAX96, sqrtRatioBX96, liquidity);
        }
    }
}
