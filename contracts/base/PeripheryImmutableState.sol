// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;

// 本项目接口 - 外围不可变状态接口
import '../interfaces/IPeripheryImmutableState.sol';

/// @title Immutable state
/// @notice Immutable state used by periphery contracts
/// @notice_zh 不可变状态 - 外围合约使用的不可变状态
/// @dev_zh 此抽象合约定义了所有外围合约共享的不可变状态变量
/// @dev_zh 这些变量在部署时设置，之后无法修改，提供了安全的常量访问
abstract contract PeripheryImmutableState is IPeripheryImmutableState {
    /// @inheritdoc IPeripheryImmutableState
    /// @dev_zh Uniswap V3 Factory 合约地址（不可变）
    /// @dev_zh 用于创建和查找池子
    address public immutable override factory;
    /// @inheritdoc IPeripheryImmutableState
    /// @dev_zh WETH9 合约地址（不可变）
    /// @dev_zh 用于 ETH 包装和解包
    address public immutable override WETH9;

    /// @notice_zh 构造函数 - 设置不可变状态
    /// @param _factory Uniswap V3 Factory 合约地址
    /// @param _WETH9 WETH9 合约地址
    constructor(address _factory, address _WETH9) {
        factory = _factory;
        WETH9 = _WETH9;
    }
}
