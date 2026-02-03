// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;
pragma abicoder v2;

// V3 核心接口 - 交换回调接口
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol';

/// @title Router token swapping functionality
/// @notice Functions for swapping tokens via Uniswap V3
/// @notice_zh Uniswap V3 交换路由器接口 - 定义代币交换功能
/// @dev_zh 此接口定义了通过 Uniswap V3 进行代币交换的所有函数
interface ISwapRouter is IUniswapV3SwapCallback {
    /// @dev_zh 精确输入单跳交换参数结构体
    struct ExactInputSingleParams {
        address tokenIn;           // @dev_zh 输入代币地址
        address tokenOut;          // @dev_zh 输出代币地址
        uint24 fee;                // @dev_zh 池子费用等级（500, 3000, 10000）
        address recipient;         // @dev_zh 接收输出代币的地址
        uint256 deadline;          // @dev_zh 交易截止时间戳
        uint256 amountIn;          // @dev_zh 精确的输入代币数量
        uint256 amountOutMinimum;  // @dev_zh 最少输出代币数量（滑点保护）
        uint160 sqrtPriceLimitX96; // @dev_zh 价格限制（平方根价格 X96 格式，0 表示无限制）
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @notice_zh 单跳精确输入交换 - 用精确的输入量交换尽可能多的输出代币
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
    /// @param_zh params 交换参数，编码为 ExactInputSingleParams 结构体
    /// @return amountOut The amount of the received token
    /// @return_zh amountOut 实际收到的输出代币数量
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);

    /// @dev_zh 精确输入多跳交换参数结构体
    struct ExactInputParams {
        bytes path;                // @dev_zh 编码的交换路径（代币地址和费用交替编码）
        address recipient;         // @dev_zh 接收最终输出代币的地址
        uint256 deadline;          // @dev_zh 交易截止时间戳
        uint256 amountIn;          // @dev_zh 精确的输入代币数量
        uint256 amountOutMinimum;  // @dev_zh 最少输出代币数量（滑点保护）
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another along the specified path
    /// @notice_zh 多跳精确输入交换 - 沿指定路径用精确的输入量交换尽可能多的输出代币
    /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactInputParams` in calldata
    /// @param_zh params 多跳交换参数，编码为 ExactInputParams 结构体
    /// @return amountOut The amount of the received token
    /// @return_zh amountOut 实际收到的最终输出代币数量
    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);

    /// @dev_zh 精确输出单跳交换参数结构体
    struct ExactOutputSingleParams {
        address tokenIn;           // @dev_zh 输入代币地址
        address tokenOut;          // @dev_zh 输出代币地址
        uint24 fee;                // @dev_zh 池子费用等级
        address recipient;         // @dev_zh 接收输出代币的地址
        uint256 deadline;          // @dev_zh 交易截止时间戳
        uint256 amountOut;         // @dev_zh 精确的输出代币数量
        uint256 amountInMaximum;   // @dev_zh 最多输入代币数量（滑点保护）
        uint160 sqrtPriceLimitX96; // @dev_zh 价格限制（平方根价格 X96 格式，0 表示无限制）
    }

    /// @notice Swaps as little as possible of one token for `amountOut` of another token
    /// @notice_zh 单跳精确输出交换 - 用尽可能少的输入量交换精确的输出代币数量
    /// @param params The parameters necessary for the swap, encoded as `ExactOutputSingleParams` in calldata
    /// @param_zh params 交换参数，编码为 ExactOutputSingleParams 结构体
    /// @return amountIn The amount of the input token
    /// @return_zh amountIn 实际使用的输入代币数量
    function exactOutputSingle(ExactOutputSingleParams calldata params) external payable returns (uint256 amountIn);

    /// @dev_zh 精确输出多跳交换参数结构体
    struct ExactOutputParams {
        bytes path;                // @dev_zh 编码的交换路径（反向，代币地址和费用交替编码）
        address recipient;         // @dev_zh 接收最终输出代币的地址
        uint256 deadline;          // @dev_zh 交易截止时间戳
        uint256 amountOut;         // @dev_zh 精确的最终输出代币数量
        uint256 amountInMaximum;   // @dev_zh 最多输入代币数量（滑点保护）
    }

    /// @notice Swaps as little as possible of one token for `amountOut` of another along the specified path (reversed)
    /// @notice_zh 多跳精确输出交换 - 沿指定路径（反向）用尽可能少的输入量交换精确的输出代币数量
    /// @param params The parameters necessary for the multi-hop swap, encoded as `ExactOutputParams` in calldata
    /// @param_zh params 多跳交换参数，编码为 ExactOutputParams 结构体
    /// @return amountIn The amount of the input token
    /// @return_zh amountIn 实际使用的输入代币数量
    function exactOutput(ExactOutputParams calldata params) external payable returns (uint256 amountIn);
}
