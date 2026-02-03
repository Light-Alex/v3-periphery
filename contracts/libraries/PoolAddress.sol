// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Provides functions for deriving a pool address from the factory, tokens, and the fee
/// @notice_zh 池地址计算库 - 提供从 factory、代币和费用推导池地址的函数
/// @dev_zh 此库使用 CREATE2 确定性计算 Uniswap V3 池子的合约地址
library PoolAddress {
    /// @dev_zh 池子初始化代码的哈希值（用于 CREATE2 地址计算）
    bytes32 internal constant POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    /// @notice The identifying key of the pool
    /// @notice_zh 池子的唯一标识密钥
    struct PoolKey {
        address token0;  // @dev_zh 池子的第一个代币地址（按地址排序）
        address token1;  // @dev_zh 池子的第二个代币地址（按地址排序）
        uint24 fee;      // @dev_zh 池子的费用等级（500, 3000, 10000）
    }

    /// @notice Returns PoolKey: the ordered tokens with the matched fee levels
    /// @notice_zh 返回池子密钥：包含排序后的代币和匹配的费用等级
    /// @param tokenA The first token of a pool, unsorted
    /// @param_zh tokenA 池子的第一个代币地址（未排序）
    /// @param tokenB The second token of a pool, unsorted
    /// @param_zh tokenB 池子的第二个代币地址（未排序）
    /// @param fee The fee level of the pool
    /// @param_zh fee 池子的费用等级
    /// @return Poolkey The pool details with ordered token0 and token1 assignments
    /// @return_zh Poolkey 池子详细信息，包含已排序的 token0 和 token1
    function getPoolKey(
        address tokenA,
        address tokenB,
        uint24 fee
    ) internal pure returns (PoolKey memory) {
        // @dev_zh 确保 token0 地址小于 token1 地址（按地址排序）
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        return PoolKey({token0: tokenA, token1: tokenB, fee: fee});
    }

    /// @notice Deterministically computes the pool address given the factory and PoolKey
    /// @notice_zh 确定性计算给定 factory 和 PoolKey 的池子地址
    /// @dev_zh 使用 CREATE2 计算地址：keccak256(0xff + factory + keccak256(token0, token1, fee) + initCodeHash)
    /// @param factory The Uniswap V3 factory contract address
    /// @param_zh factory Uniswap V3 Factory 合约地址
    /// @param key The PoolKey
    /// @param_zh key 池子密钥
    /// @return pool The contract address of the V3 pool
    /// @return_zh pool V3 池子的合约地址
    function computeAddress(address factory, PoolKey memory key) internal pure returns (address pool) {
        // @dev_zh 验证 token0 地址小于 token1 地址
        require(key.token0 < key.token1);
        // @dev_zh 使用 CREATE2 确定性计算池子地址
        pool = address(
            uint256(
                keccak256(
                    abi.encodePacked(
                        hex'ff',                           // @dev_zh CREATE2 前缀
                        factory,                         // @dev_zh Factory 地址
                        keccak256(abi.encode(key.token0, key.token1, key.fee)),  // @dev_zh 编码的代币和费用
                        POOL_INIT_CODE_HASH             // @dev_zh 池子初始化代码哈希
                    )
                )
            )
        );
    }
}
