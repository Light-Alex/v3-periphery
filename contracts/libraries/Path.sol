// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.0;

// 库文件 - 字节操作工具
import './BytesLib.sol';

/// @title Functions for manipulating path data for multihop swaps
/// @notice_zh 路径处理库 - 用于操作多跳交换的路径数据
/// @dev_zh 此库提供了编码和解码 Uniswap V3 多跳交换路径的所有函数
/// @dev_zh 路径格式：[token0][fee][token1][fee][token2]...
library Path {
    // 使用 BytesLib 扩展 bytes 类型
    using BytesLib for bytes;

    /// @dev The length of the bytes encoded address
    /// @dev_zh 编码地址的字节长度（20 字节）
    uint256 private constant ADDR_SIZE = 20;
    /// @dev The length of the bytes encoded fee
    /// @dev_zh 编码费用的字节长度（3 字节）
    uint256 private constant FEE_SIZE = 3;

    /// @dev The offset of a single token address and pool fee
    /// @dev_zh 单个代币地址和池子费用的偏移量
    uint256 private constant NEXT_OFFSET = ADDR_SIZE + FEE_SIZE;
    /// @dev The offset of an encoded pool key
    /// @dev_zh 编码池子密钥的偏移量
    uint256 private constant POP_OFFSET = NEXT_OFFSET + ADDR_SIZE;
    /// @dev The minimum length of an encoding that contains 2 or more pools
    /// @dev_zh 包含 2 个或更多池子的编码的最小长度
    uint256 private constant MULTIPLE_POOLS_MIN_LENGTH = POP_OFFSET + NEXT_OFFSET;

    /// @notice Returns true iff the path contains two or more pools
    /// @notice_zh 检查路径是否包含两个或更多池子
    /// @param path The encoded swap path
    /// @param_zh path 编码的交换路径
    /// @return True if path contains two or more pools, otherwise false
    /// @return_zh 如果路径包含两个或更多池子返回 true，否则返回 false
    function hasMultiplePools(bytes memory path) internal pure returns (bool) {
        return path.length >= MULTIPLE_POOLS_MIN_LENGTH;
    }

    /// @notice Returns the number of pools in the path
    /// @notice_zh 返回路径中的池子数量
    /// @param path The encoded swap path
    /// @param_zh path 编码的交换路径
    /// @return The number of pools in the path
    /// @return_zh 路径中的池子数量
    function numPools(bytes memory path) internal pure returns (uint256) {
        // Ignore the first token address. From then on every fee and token offset indicates a pool.
        // @dev_zh 忽略第一个代币地址。之后每个费用和代币偏移量表示一个池子
        return ((path.length - ADDR_SIZE) / NEXT_OFFSET);
    }

    /// @notice Decodes the first pool in path
    /// @notice_zh 解码路径中的第一个池子
    /// @param path The bytes encoded swap path
    /// @param_zh path 编码的交换路径
    /// @return tokenA The first token of the given pool
    /// @return_zh tokenA 池子的第一个代币地址
    /// @return tokenB The second token of the given pool
    /// @return_zh tokenB 池子的第二个代币地址
    /// @return fee The fee level of the pool
    /// @return_zh fee 池子的费用等级
    function decodeFirstPool(bytes memory path)
        internal
        pure
        returns (
            address tokenA,
            address tokenB,
            uint24 fee
        )
    {
        tokenA = path.toAddress(0);           // @dev_zh 读取第一个代币地址
        fee = path.toUint24(ADDR_SIZE);      // @dev_zh 读取费用等级
        tokenB = path.toAddress(NEXT_OFFSET); // @dev_zh 读取第二个代币地址
    }

    /// @notice Gets the segment corresponding to the first pool in the path
    /// @notice_zh 获取路径中第一个池子对应的数据段
    /// @param path The bytes encoded swap path
    /// @param_zh path 编码的交换路径
    /// @return The segment containing all data necessary to target the first pool in the path
    /// @return_zh 包含定位第一个池子所需所有数据的数据段
    function getFirstPool(bytes memory path) internal pure returns (bytes memory) {
        return path.slice(0, POP_OFFSET);
    }

    /// @notice Skips a token + fee element from the buffer and returns the remainder
    /// @notice_zh 跳过一个代币+费用元素，返回剩余的路径
    /// @param path The swap path
    /// @param_zh path 交换路径
    /// @return The remaining token + fee elements in the path
    /// @return_zh 路径中剩余的代币+费用元素
    function skipToken(bytes memory path) internal pure returns (bytes memory) {
        return path.slice(NEXT_OFFSET, path.length - NEXT_OFFSET);
    }
}
