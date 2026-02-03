// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

// 本项目接口 - 多重调用接口
import '../interfaces/IMulticall.sol';

/// @title Multicall
/// @notice Enables calling multiple methods in a single call to the contract
/// @notice_zh 多重调用 - 允许在单次交易中调用多个方法
/// @dev_zh 此抽象合约实现了多重调用功能，可以批量执行多个合约调用，节省交易费用和Gas
/// @dev_zh 这是在单笔交易中执行多个操作的核心功能
abstract contract Multicall is IMulticall {
    /// @inheritdoc IMulticall
    /// @notice_zh 在单次交易中调用多个方法
    /// @dev_zh 此函数循环执行 delegatecall，每个调用都会修改合约状态
    /// @param data 包含多个调用数据的字节数组
    /// @return results 每个调用的返回值数组
    function multicall(bytes[] calldata data) public payable override returns (bytes[] memory results) {
        results = new bytes[](data.length);
        // @dev_zh 循环执行每个调用
        for (uint256 i = 0; i < data.length; i++) {
            // @dev_zh 使用 delegatecall 执行调用，允许修改合约状态
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);

            if (!success) {
                // Next 5 lines from https://ethereum.stackexchange.com/a/83577
                // @dev_zh 如果调用失败，解析错误信息并回滚
                if (result.length < 68) revert();
                assembly {
                    result := add(result, 0x04)
                }
                revert(abi.decode(result, (string)));
            }

            results[i] = result;
        }
    }
}
