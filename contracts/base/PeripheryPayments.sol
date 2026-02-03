// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;

// OpenZeppelin 接口 - ERC20 接口
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

// 本项目接口 - 外围支付接口
import '../interfaces/IPeripheryPayments.sol';
// 外部接口 - WETH9 接口
import '../interfaces/external/IWETH9.sol';

// 库文件 - 转账辅助工具
import '../libraries/TransferHelper.sol';

// 基础合约 - 不可变状态
import './PeripheryImmutableState.sol';

/// @title Periphery Payments
/// @notice_zh 外围支付 - 处理代币和 ETH 的支付
/// @dev_zh 此抽象合约提供了处理代币和 ETH 支付的核心功能
/// @dev_zh 支持 WETH9 解包、代币清理、ETH 退款等操作
abstract contract PeripheryPayments is IPeripheryPayments, PeripheryImmutableState {
    /// @notice_zh 接收 ETH - 只接受来自 WETH9 的 ETH
    /// @dev_zh 当 WETH9 解包时会发送 ETH 到此合约
    receive() external payable {
        require(msg.sender == WETH9, 'Not WETH9');
    }

    /// @inheritdoc IPeripheryPayments
    /// @notice_zh 解包 WETH9 并发送 ETH 给接收者
    /// @dev_zh 将合约中的 WETH9 解包为 ETH 并发送给指定地址
    /// @param amountMinimum 要求的最少 WETH9 数量（检查用）
    /// @param_zh amountMinimum 最少要解包的 WETH9 数量
    /// @param recipient 接收 ETH 的地址
    /// @param_zh recipient 接收 ETH 的地址
    function unwrapWETH9(uint256 amountMinimum, address recipient) public payable override {
        // @dev_zh 获取合约中的 WETH9 余额
        uint256 balanceWETH9 = IWETH9(WETH9).balanceOf(address(this));
        // @dev_zh 检查余额是否满足最小值要求
        require(balanceWETH9 >= amountMinimum, 'Insufficient WETH9');

        if (balanceWETH9 > 0) {
            // @dev_zh 解包 WETH9 为 ETH
            IWETH9(WETH9).withdraw(balanceWETH9);
            // @dev_zh 发送 ETH 给接收者
            TransferHelper.safeTransferETH(recipient, balanceWETH9);
        }
    }

    /// @inheritdoc IPeripheryPayments
    /// @notice_zh 清理合约中的代币并发送给接收者
    /// @dev_zh 将合约中剩余的代币发送给指定地址
    /// @param token 要清理的代币地址
    /// @param amountMinimum 要求的最少代币数量（检查用）
    /// @param_zh token 代币地址
    /// @param_zh amountMinimum 最少代币数量
    /// @param recipient 接收代币的地址
    /// @param_zh recipient 接收代币的地址
    function sweepToken(
        address token,
        uint256 amountMinimum,
        address recipient
    ) public payable override {
        // @dev_zh 获取合约中的代币余额
        uint256 balanceToken = IERC20(token).balanceOf(address(this));
        // @dev_zh 检查余额是否满足最小值要求
        require(balanceToken >= amountMinimum, 'Insufficient token');

        if (balanceToken > 0) {
            // @dev_zh 转账所有代币给接收者
            TransferHelper.safeTransfer(token, recipient, balanceToken);
        }
    }

    /// @inheritdoc IPeripheryPayments
    /// @notice_zh 退还剩余的 ETH 给调用者
    /// @dev_zh 将合约中的剩余 ETH 发送回调用者
    function refundETH() external payable override {
        // @dev_zh 发送所有剩余 ETH 给调用者
        if (address(this).balance > 0) TransferHelper.safeTransferETH(msg.sender, address(this).balance);
    }

    /// @param token The token to pay
    /// @param payer The entity that must pay
    /// @param recipient The entity that will receive payment
    /// @param value The amount to pay
    /// @notice_zh 支付代币或 ETH 的内部函数
    /// @dev_zh 此函数处理三种支付方式：
    /// @dev_zh 1. WETH9：使用合约中的 ETH，先包装成 WETH9 再发送
    /// @dev_zh 2. 内部代币：直接发送合约中已有的代币（用于多跳交换）
    /// @dev_zh 3. 外部代币：从 payer 地址拉取代币
    /// @param token 要支付的代币地址
    /// @param payer 必须支付代币的地址
    /// @param recipient 接收代币的地址
    /// @param value 要支付的数量
    function pay(
        address token,
        address payer,
        address recipient,
        uint256 value
    ) internal {
        if (token == WETH9 && address(this).balance >= value) {
            // pay with WETH9
            // @dev_zh 使用合约中的 ETH，包装为 WETH9 并发送
            IWETH9(WETH9).deposit{value: value}(); // wrap only what is needed to pay
            IWETH9(WETH9).transfer(recipient, value);
        } else if (payer == address(this)) {
            // pay with tokens already in the contract (for the exact input multihop case)
            // @dev_zh 使用合约中已有的代币支付（用于多跳交换的精确输入）
            TransferHelper.safeTransfer(token, recipient, value);
        } else {
            // pull payment
            // @dev_zh 从 payer 地址拉取代币（外部代币支付）
            TransferHelper.safeTransferFrom(token, payer, recipient, value);
        }
    }
}
