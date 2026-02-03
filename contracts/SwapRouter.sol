// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

// V3 核心库导入 - 安全类型转换
import '@uniswap/v3-core/contracts/libraries/SafeCast.sol';
// V3 核心库导入 - Tick 数学计算
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';
// V3 核心接口 - 池子接口
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

// 本项目接口 - 交换路由器接口
import './interfaces/ISwapRouter.sol';
// 基础合约 - 不可变状态（factory 和 WETH9 地址）
import './base/PeripheryImmutableState.sol';
// 基础合约 - 验证功能（截止时间检查）
import './base/PeripheryValidation.sol';
// 基础合约 - 带费用的支付功能
import './base/PeripheryPaymentsWithFee.sol';
// 基础合约 - 多重调用功能
import './base/Multicall.sol';
// 基础合约 - 自许可功能
import './base/SelfPermit.sol';
// 库文件 - 路径编码/解码
import './libraries/Path.sol';
// 库文件 - 池地址计算
import './libraries/PoolAddress.sol';
// 库文件 - 回调验证
import './libraries/CallbackValidation.sol';
// 外部接口 - WETH9 接口
import './interfaces/external/IWETH9.sol';

/// @title Uniswap V3 Swap Router
/// @notice Router for stateless execution of swaps against Uniswap V3
/// @notice_zh Uniswap V3 交换路由器 - 用于执行无状态的代币交换
/// @dev_zh 此合约提供了与 Uniswap V3 池交互的核心功能，支持单跳和多跳交换
contract SwapRouter is
    ISwapRouter,
    PeripheryImmutableState,
    PeripheryValidation,
    PeripheryPaymentsWithFee,
    Multicall,
    SelfPermit
{
    // 使用 Path 库扩展 bytes 类型 - 用于路径编码/解码
    using Path for bytes;
    // 使用 SafeCast 库扩展 uint256 类型 - 用于安全类型转换
    using SafeCast for uint256;

    /// @dev Used as the placeholder value for amountInCached, because the computed amount in for an exact output swap
    /// can never actually be this value
    /// @dev_zh 用作 amountInCached 的占位值，因为精确输出交换计算出的输入量永远不会等于此值
    uint256 private constant DEFAULT_AMOUNT_IN_CACHED = type(uint256).max;

    /// @dev Transient storage variable used for returning the computed amount in for an exact output swap.
    /// @dev_zh 临时存储变量，用于返回精确输出交换计算出的输入量
    uint256 private amountInCached = DEFAULT_AMOUNT_IN_CACHED;

    /// @notice_zh 构造函数 - 初始化 factory 和 WETH9 地址
    /// @param _factory Uniswap V3 Factory 合约地址
    /// @param _WETH9 WETH9 合约地址
    constructor(address _factory, address _WETH9) PeripheryImmutableState(_factory, _WETH9) {}

    /// @dev Returns the pool for the given token pair and fee. The pool contract may or may not exist.
    /// @dev_zh 根据代币对和费用等级返回对应的池子地址。池子合约可能存在也可能不存在。
    /// @param tokenA 第一个代币地址
    /// @param tokenB 第二个代币地址
    /// @param fee 费用等级（500, 3000, 10000）
    /// @return pool 池子合约地址
    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) private view returns (IUniswapV3Pool) {
        return IUniswapV3Pool(PoolAddress.computeAddress(factory, PoolAddress.getPoolKey(tokenA, tokenB, fee)));
    }

    /// @dev_zh 交换回调数据结构 - 用于在回调中传递路径和支付者信息
    struct SwapCallbackData {
        bytes path;     // @dev_zh 交换路径（编码的代币地址和费用）
        address payer;  // @dev_zh 支付代币的地址
    }

    /// @inheritdoc IUniswapV3SwapCallback
    /// @dev_zh Uniswap V3 池子调用的回调函数，用于在交换过程中支付代币
    /// @param amount0Delta token0 的数量变化（正数表示需要接收，负数表示需要支付）
    /// @param amount1Delta token1 的数量变化（正数表示需要接收，负数表示需要支付）
    /// @param _data 编码的回调数据，包含路径和支付者信息
    /// @dev_zh 此函数是交换的核心，池子在交换时会调用此函数来获取输入代币
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata _data
    ) external override {
        // @dev_zh 要求至少有一个代币数量大于 0（完全在 0 流动性区域的交换不被支持）
        require(amount0Delta > 0 || amount1Delta > 0); // swaps entirely within 0-liquidity regions are not supported

        // @dev_zh 解码回调数据
        SwapCallbackData memory data = abi.decode(_data, (SwapCallbackData));
        (address tokenIn, address tokenOut, uint24 fee) = data.path.decodeFirstPool();

        // @dev_zh 验证回调确实来自有效的池子
        CallbackValidation.verifyCallback(factory, tokenIn, tokenOut, fee);

        // @dev_zh 确定是精确输入交换还是精确输出交换，以及需要支付的代币数量
        (bool isExactInput, uint256 amountToPay) =
            amount0Delta > 0
                ? (tokenIn < tokenOut, uint256(amount0Delta))  // tokenIn < tokenOut: 精确输入; tokenIn >= tokenOut: 精确输出
                : (tokenOut < tokenIn, uint256(amount1Delta));

        if (isExactInput) {
            // @dev_zh 精确输入交换：直接支付代币给池子
            pay(tokenIn, data.payer, msg.sender, amountToPay);
        } else {
            // @dev_zh 精确输出交换：检查是否需要多跳交换
            // either initiate the next swap or pay
            if (data.path.hasMultiplePools()) {
                // @dev_zh 如果有多个池子，跳过第一个代币和其费用，计算剩余路径
                // 路径格式: [token0][fee][token1][fee][token2]...
                data.path = data.path.skipToken();
                exactOutputInternal(amountToPay, msg.sender, 0, data);
            } else {
                // @dev_zh 最后一个池子，缓存输入量并支付
                amountInCached = amountToPay;
                tokenIn = tokenOut; // swap in/out because exact output swaps are reversed
                pay(tokenIn, data.payer, msg.sender, amountToPay);
            }
        }
    }

    /// @dev Performs a single exact input swap
    /// @dev_zh 执行单跳精确输入交换 - 知道输入量，计算输出量
    /// @param amountIn 精确的输入代币数量
    /// @param recipient 接收输出代币的地址（如果是 address(0) 则发送到此路由合约）
    /// @param sqrtPriceLimitX96 价格限制（平方根价格 X96 格式，0 表示无限制）
    /// @param data 包含路径和支付者信息的回调数据
    /// @return amountOut 计算得到的输出代币数量
    function exactInputInternal(
        uint256 amountIn,
        address recipient,
        uint160 sqrtPriceLimitX96,
        SwapCallbackData memory data
    ) private returns (uint256 amountOut) {
        // allow swapping to the router address with address 0
        // @dev_zh 允许使用地址 0 表示交换到路由器地址
        if (recipient == address(0)) recipient = address(this);

        // @dev_zh 解码路径中的第一个池子信息
        (address tokenIn, address tokenOut, uint24 fee) = data.path.decodeFirstPool();

        // @dev_zh 确定交换方向：true 表示用 token0 换 token1，false 表示相反
        bool zeroForOne = tokenIn < tokenOut;

        // @dev_zh 调用池子的 swap 函数执行交换
        (int256 amount0, int256 amount1) =
            getPool(tokenIn, tokenOut fee).swap(
                recipient,
                zeroForOne,
                amountIn.toInt256(),
                sqrtPriceLimitX96 == 0
                    ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                    : sqrtPriceLimitX96,
                abi.encode(data)
            );

        // @dev_zh 返回输出代币数量（根据交换方向选择 amount0 或 amount1 的负值）
        return uint256(-(zeroForOne ? amount1 : amount0));
    }

    /// @inheritdoc ISwapRouter
    /// @notice_zh 单池精确输入交换 - 在单个池子中用精确的输入量交换代币
    /// @dev_zh 此函数是最常用的交换方式，用户指定要输入的代币数量，合约计算输出量
    /// @param params 交换参数结构体，包含：
    ///   - tokenIn: 输入代币地址
    ///   - tokenOut: 输出代币地址
    ///   - fee: 池子费用等级（500, 3000, 10000）
    ///   - recipient: 接收输出代币的地址
    ///   - deadline: 交易截止时间戳
    ///   - amountIn: 精确的输入代币数量
    ///   - amountOutMinimum: 最少输出代币数量（滑点保护）
    ///   - sqrtPriceLimitX96: 价格限制（0 表示无限制）
    /// @return amountOut 实际输出的代币数量
    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (uint256 amountOut)
    {
        // @dev_zh 编码路径并执行内部交换
        amountOut = exactInputInternal(
            params.amountIn,
            params.recipient,
            params.sqrtPriceLimitX96,
            SwapCallbackData({path: abi.encodePacked(params.tokenIn, params.fee, params.tokenOut), payer: msg.sender})
        );
        // @dev_zh 检查输出量是否满足最小值要求（滑点保护）
        require(amountOut >= params.amountOutMinimum, 'Too little received');
    }

    /// @inheritdoc ISwapRouter
    /// @notice_zh 多跳精确输入交换 - 通过多个池子进行代币交换
    /// @dev_zh 此函数支持复杂的交换路径，例如 USDC → USDT → DAI
    /// @dev_zh 每个中间交换的输出会成为下一个交换的输入
    /// @param params 交换参数结构体，包含：
    ///   - path: 编码的交换路径（代币地址和费用交替编码）
    ///   - recipient: 接收最终输出代币的地址
    ///   - deadline: 交易截止时间戳
    ///   - amountIn: 精确的输入代币数量
    ///   - amountOutMinimum: 最少输出代币数量（滑点保护）
    /// @return amountOut 实际最终输出的代币数量
    function exactInput(ExactInputParams memory params)
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (uint256 amountOut)
    {
        address payer = msg.sender; // msg.sender pays for the first hop
        // @dev_zh msg.sender 为第一个跳跃支付

        // @dev_zh 循环执行每个池子的交换
        while (true) {
            bool hasMultiplePools = params.path.hasMultiplePools();

            // the outputs of prior swaps become the inputs to subsequent ones
            // @dev_zh 前一个交换的输出会成为后一个交换的输入
            params.amountIn = exactInputInternal(
                params.amountIn,
                hasMultiplePools ? address(this) : params.recipient, // for intermediate swaps, this contract custodies
                0,
                SwapCallbackData({
                    path: params.path.getFirstPool(), // only the first pool in the path is necessary
                    payer: payer
                })
            );

            // decide whether to continue or terminate
            // @dev_zh 决定是继续还是终止
            if (hasMultiplePools) {
                payer = address(this); // at this point, the caller has paid
                // @dev_zh 此时调用者已经支付，后续交换由此合约托管
                params.path = params.path.skipToken();
            } else {
                amountOut = params.amountIn;
                break;
            }
        }

        // @dev_zh 检查最终输出量是否满足最小值要求
        require(amountOut >= params.amountOutMinimum, 'Too little received');
    }

    /// @dev Performs a single exact output swap
    /// @dev_zh 执行单跳精确输出交换 - 知道输出量，计算需要的输入量
    /// @param amountOut 精确的输出代币数量
    /// @param recipient 接收输出代币的地址
    /// @param sqrtPriceLimitX96 价格限制（平方根价格 X96 格式，0 表示无限制）
    /// @param data 包含路径和支付者信息的回调数据
    /// @return amountIn 计算得到的需要输入的代币数量
    function exactOutputInternal(
        uint256 amountOut,
        address recipient,
        uint160 sqrtPriceLimitX96,
        SwapCallbackData memory data
    ) private returns (uint256 amountIn) {
        // allow swapping to the router address with address 0
        // @dev_zh 允许使用地址 0 表示交换到路由器地址
        if (recipient == address(0)) recipient = address(this);

        // @dev_zh 解码路径（注意：精确输出交换的路径是反向的）
        (address tokenOut, address tokenIn, uint24 fee) = data.path.decodeFirstPool();

        // @dev_zh 确定交换方向
        bool zeroForOne = tokenIn < tokenOut;

        // @dev_zh 调用池子的 swap 函数，注意 amountOut 是负数
        (int256 amount0Delta, int256 amount1Delta) =
            getPool(tokenIn, tokenOut, fee).swap(
                recipient,
                zeroForOne,
                -amountOut.toInt256(),
                sqrtPriceLimitX96 == 0
                    ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                    : sqrtPriceLimitX96,
                abi.encode(data)
            );

        uint256 amountOutReceived;
        // @dev_zh 根据交换方向提取输入和输出量
        (amountIn, amountOutReceived) = zeroForOne
            ? (uint256(amount0Delta), uint256(-amount1Delta))
            : (uint256(amount1Delta), uint256(-amount0Delta));

        // it's technically possible to not receive the full output amount,
        // so if no price limit has been specified, require this possibility away
        // @dev_zh 技术上可能无法接收到完整的输出量，所以如果没有指定价格限制，要求必须接收完整输出
        if (sqrtPriceLimitX96 == 0) require(amountOutReceived == amountOut);
    }

    /// @inheritdoc ISwapRouter
    /// @notice_zh 单池精确输出交换 - 在单个池子中用精确的输出量交换代币
    /// @dev_zh 用户指定要获得的输出代币数量，合约计算需要的输入量
    /// @dev_zh 此方式适合希望获得确定数量代币的场景
    /// @param params 交换参数结构体，包含：
    ///   - tokenIn: 输入代币地址
    ///   - tokenOut: 输出代币地址
    ///   - fee: 池子费用等级（500, 3000, 10000）
    ///   - recipient: 接收输出代币的地址
    ///   - deadline: 交易截止时间戳
    ///   - amountOut: 精确的输出代币数量
    ///   - amountInMaximum: 最多输入代币数量（滑点保护）
    ///   - sqrtPriceLimitX96: 价格限制（0 表示无限制）
    /// @return amountIn 实际需要的输入代币数量
    function exactOutputSingle(ExactOutputSingleParams calldata params)
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (uint256 amountIn)
    {
        // avoid an SLOAD by using the swap return data
        // @dev_zh 通过使用交换返回数据来避免 SLOAD 操作
        amountIn = exactOutputInternal(
            params.amountOut,
            params.recipient,
            params.sqrtPriceLimitX96,
            SwapCallbackData({path: abi.encodePacked(params.tokenOut, params.fee, params.tokenIn), payer: msg.sender})
        );

        // @dev_zh 检查输入量是否超过最大值限制
        require(amountIn <= params.amountInMaximum, 'Too much requested');
        // has to be reset even though we don't use it in the single hop case
        // @dev_zh 即使在单跳情况下不使用此变量，也必须重置它
        amountInCached = DEFAULT_AMOUNT_IN_CACHED;
    }

    /// @inheritdoc ISwapRouter
    /// @notice_zh 多跳精确输出交换 - 通过多个池子进行代币交换
    /// @dev_zh 用户指定最终要获得的输出代币数量，合约倒推计算需要的输入量
    /// @dev_zh 交换路径是反向执行的（从最后的池子开始）
    /// @param params 交换参数结构体，包含：
    ///   - path: 编码的交换路径（代币地址和费用交替编码），例如: [token0][fee][token1][fee][token2] token0为输出代币地址, token2为输入代币地址
    ///   - recipient: 接收最终输出代币的地址
    ///   - deadline: 交易截止时间戳
    ///   - amountOut: 精确的最终输出代币数量
    ///   - amountInMaximum: 最多输入代币数量（滑点保护）
    /// @return amountIn 实际需要的输入代币数量
    /// 流程: 
    /// 1. pool合约把token0代币转给接收最终输出代币的地址, 调用uniswapV3SwapCallback要求payer转入token1代币(计算payer需要转多少token1); [token0][fee][token1] <- 第一次交换
    /// 2. pool合约把token1代币转给自己, 调用uniswapV3SwapCallback要求payer转入token2代币(payer转入token2); [token1][fee][token2] <- 第二次交换

    function exactOutput(ExactOutputParams calldata params)
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (uint256 amountIn)
    {
        // it's okay that the payer is fixed to msg.sender here, as they're only paying for the "final" exact output
        // swap, which happens first, and subsequent swaps are paid for within nested callback frames
        // @dev_zh 支付者固定为 msg.sender 是可以的，因为他们只需为"最终的"精确输出交换支付
        // @dev_zh 这个交换首先发生，后续的交换在嵌套的回调帧中支付
        exactOutputInternal(
            params.amountOut,
            params.recipient,
            0,
            SwapCallbackData({path: params.path, payer: msg.sender})
        );

        // @dev_zh 从缓存变量中获取输入量
        amountIn = amountInCached;
        // @dev_zh 检查输入量是否超过最大值限制
        require(amountIn <= params.amountInMaximum, 'Too much requested');
        // @dev_zh 重置缓存变量
        amountInCached = DEFAULT_AMOUNT_IN_CACHED;
    }
}
