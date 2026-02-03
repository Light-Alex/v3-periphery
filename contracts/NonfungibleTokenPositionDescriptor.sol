// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

// V3 核心接口 - 池子接口
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
// Uniswap 库 - ERC20 代币命名工具
import '@uniswap/lib/contracts/libraries/SafeERC20Namer.sol';

// 库文件 - 链 ID
import './libraries/ChainId.sol';
// 本项目接口 - NFT 位置管理器接口
import './interfaces/INonfungiblePositionManager.sol';
// 本项目接口 - NFT 描述符接口
import './interfaces/INonfungibleTokenPositionDescriptor.sol';
// 本项目接口 - ERC20 元数据接口
import './interfaces/IERC20Metadata.sol';
// 库文件 - 池地址计算
import './libraries/PoolAddress.sol';
// 库文件 - NFT 描述符生成
import './libraries/NFTDescriptor.sol';
// 库文件 - 代币比率排序
import './libraries/TokenRatioSortOrder.sol';

/// @title Describes NFT token positions
/// @notice Produces a string containing the data URI for a JSON metadata string
/// @notice_zh NFT 位置描述符 - 为流动性位置 NFT 生成元数据 URI
/// @dev_zh 此合约负责生成描述流动性位置的 JSON 元数据，用于在 NFT 市场展示
/// @dev_zh 元数据包含代币信息、价格区间、当前价格等详细信息
contract NonfungibleTokenPositionDescriptor is INonfungibleTokenPositionDescriptor {
    // @dev_zh 主网稳定币和代币地址常量
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;  // @dev_zh DAI 稳定币地址
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;  // @dev_zh USDC 稳定币地址
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;  // @dev_zh USDT 稳定币地址
    address private constant TBTC = 0x8dAEBADE922dF735c38C80C7eBD708Af50815fAa;  // @dev_zh tBTC 代币地址
    address private constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;  // @dev_zh WBTC 代币地址

    /// @dev_zh WETH9 合约地址（不可变）
    address public immutable WETH9;
    /// @dev A null-terminated string
    /// @dev_zh 原生货币标签字节（用于显示"ETH"等）
    bytes32 public immutable nativeCurrencyLabelBytes;

    /// @notice_zh 构造函数 - 初始化合约参数
    /// @param _WETH9 WETH9 合约地址
    /// @param _nativeCurrencyLabelBytes 原生货币标签字节（如"ETH"）
    constructor(address _WETH9, bytes32 _nativeCurrencyLabelBytes) {
        WETH9 = _WETH9;
        nativeCurrencyLabelBytes = _nativeCurrencyLabelBytes;
    }

    /// @notice Returns the native currency label as a string
    /// @notice_zh 获取原生货币标签字符串
    /// @dev_zh 将字节32转换为字符串，用于显示原生货币名称（如"ETH"）
    /// @return 原生货币标签字符串
    function nativeCurrencyLabel() public view returns (string memory) {
        // @dev_zh 计算字符串长度（遇到 null 终止符为止）
        uint256 len = 0;
        while (len < 32 && nativeCurrencyLabelBytes[len] != 0) {
            len++;
        }
        // @dev_zh 创建新的字节数组并复制数据
        bytes memory b = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            b[i] = nativeCurrencyLabelBytes[i];
        }
        return string(b);
    }

    /// @inheritdoc INonfungibleTokenPositionDescriptor
    /// @notice_zh 生成 NFT 的 tokenURI 元数据
    /// @dev_zh 此函数构造包含位置信息的 JSON 元数据 URI，用于 NFT 市场展示
    /// @param positionManager NFT 位置管理器合约地址
    /// @param tokenId NFT token ID
    /// @return tokenURI 包含位置元数据的 data URI 字符串
    function tokenURI(INonfungiblePositionManager positionManager, uint256 tokenId)
        external
        view
        override
        returns (string memory)
    {
        // @dev_zh 从位置管理器获取位置数据
        (, , address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, , , , , ) =
            positionManager.positions(tokenId);

        // @dev_zh 计算池子地址
        IUniswapV3Pool pool =
            IUniswapV3Pool(
                PoolAddress.computeAddress(
                    positionManager.factory(),
                    PoolAddress.PoolKey({token0: token0, token1: token1, fee: fee})
                )
            );

        // @dev_zh 确定代币比率顺序（哪个是报价代币，哪个是基础代币）
        bool _flipRatio = flipRatio(token0, token1, ChainId.get());
        address quoteTokenAddress = !_flipRatio ? token1 : token0;  // @dev_zh 报价代币地址
        address baseTokenAddress = !_flipRatio ? token0 : token1;    // @dev_zh 基础代币地址
        (, int24 tick, , , , , ) = pool.slot0();  // @dev_zh 获取当前 tick（价格）

        // @dev_zh 调用 NFTDescriptor 库构造 tokenURI
        // 最终生成的 tokenURI 类似：data:application/json;base64,eyJ...（编码的JSON）
        // 解码后的 JSON 包含：
        // {
        // "name": "Uniswap V3 Position",
        // "description": "...",
        // "image": "data:image/svg+xml;base64,PHN2Zy...（SVG 图像）"
        // }
        return
            NFTDescriptor.constructTokenURI(
                NFTDescriptor.ConstructTokenURIParams({
                    tokenId: tokenId,
                    quoteTokenAddress: quoteTokenAddress,
                    baseTokenAddress: baseTokenAddress,
                    // @dev_zh 获取代币符号（如果是 WETH9 则使用原生货币标签）
                    quoteTokenSymbol: quoteTokenAddress == WETH9
                        ? nativeCurrencyLabel()
                        : SafeERC20Namer.tokenSymbol(quoteTokenAddress),
                    baseTokenSymbol: baseTokenAddress == WETH9
                        ? nativeCurrencyLabel()
                        : SafeERC20Namer.tokenSymbol(baseTokenAddress),
                    // @dev_zh 获取代币小数位数
                    quoteTokenDecimals: IERC20Metadata(quoteTokenAddress).decimals(),
                    baseTokenDecimals: IERC20Metadata(baseTokenAddress).decimals(),
                    flipRatio: _flipRatio,
                    tickLower: tickLower,    // @dev_zh 价格区间下限
                    tickUpper: tickUpper,    // @dev_zh 价格区间上限
                    tickCurrent: tick,       // @dev_zh 当前价格 tick
                    tickSpacing: pool.tickSpacing(),  // @dev_zh tick 间距
                    fee: fee,                // @dev_zh 池子费用等级
                    poolAddress: address(pool)  // @dev_zh 池子地址
                })
            );
    }

    /// @notice_zh 判断是否需要翻转代币比率
    /// @dev_zh 此函数决定在显示价格时哪个代币作为分子，哪个作为分母
    /// @param token0 池子的第一个代币地址
    /// @param token1 池子的第二个代币地址
    /// @param chainId 链 ID
    /// @return 是否需要翻转比率（true 表示 token1 作为报价代币）
    function flipRatio(
        address token0,
        address token1,
        uint256 chainId
    ) public view returns (bool) {
        return tokenRatioPriority(token0, chainId) > tokenRatioPriority(token1, chainId);
    }

    /// @notice_zh 获取代币在价格比率中的优先级
    /// @dev_zh 此函数根据代币类型返回优先级值，用于决定价格显示方式
    /// @dev_zh 优先级越高，越可能作为报价代币（分子）
    /// @param token 代币地址
    /// @param chainId 链 ID
    /// @return 优先级值（正值表示作为分子，负值表示作为分母）
    function tokenRatioPriority(address token, uint256 chainId) public view returns (int256) {
        // @dev_zh WETH9 总是作为分母
        if (token == WETH9) {
            return TokenRatioSortOrder.DENOMINATOR;
        }
        // @dev_zh 以太坊主网的特定代币优先级
        if (chainId == 1) {
            if (token == USDC) {
                return TokenRatioSortOrder.NUMERATOR_MOST;  // @dev_zh USDC 优先级最高（分子）
            } else if (token == USDT) {
                return TokenRatioSortOrder.NUMERATOR_MORE;  // @dev_zh USDT 次高优先级
            } else if (token == DAI) {
                return TokenRatioSortOrder.NUMERATOR;  // @dev_zh DAI 普通分子优先级
            } else if (token == TBTC) {
                return TokenRatioSortOrder.DENOMINATOR_MORE;  // @dev_zh tBTC 分母次高优先级
            } else if (token == WBTC) {
                return TokenRatioSortOrder.DENOMINATOR_MOST;  // @dev_zh WBTC 分母最高优先级
            } else {
                return 0;  // @dev_zh 其他代币默认优先级
            }
        }
        // @dev_zh 其他链的代币返回默认优先级
        return 0;
    }
}
