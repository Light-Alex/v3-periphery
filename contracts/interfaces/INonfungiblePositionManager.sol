// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;
pragma abicoder v2;

// OpenZeppelin 接口 - ERC721 元数据接口
import '@openzeppelin/contracts/token/ERC721/IERC721Metadata.sol';
// OpenZeppelin 接口 - ERC721 可枚举接口
import '@openzeppelin/contracts/token/ERC721/IERC721Enumerable.sol';

// 本项目接口 - 池初始化接口
import './IPoolInitializer.sol';
// 本项目接口 - ERC721 许可接口
import './IERC721Permit.sol';
// 本项目接口 - 外围支付接口
import './IPeripheryPayments.sol';
// 本项目接口 - 外围不可变状态接口
import './IPeripheryImmutableState.sol';

/// @title Non-fungible token for positions
/// @notice Wraps Uniswap V3 positions in a non-fungible token interface which allows for them to be transferred
/// and authorized.
/// @notice_zh NFT 位置管理器接口 - 将 Uniswap V3 流动性位置包装为 ERC721 非同质化代币
/// @dev_zh 此接口允许流动性位置被转移和授权，每个位置对应一个唯一的 NFT
interface INonfungiblePositionManager is
    IPoolInitializer,
    IPeripheryPayments,
    IPeripheryImmutableState,
    IERC721Metadata,
    IERC721Enumerable,
    IERC721Permit
{
    /// @notice Emitted when liquidity is increased for a position NFT
    /// @dev Also emitted when a token is minted
    /// @notice_zh 当位置 NFT 的流动性增加时触发
    /// @dev_zh 铸造新 NFT 时也会触发此事件
    /// @param tokenId The ID of the token for which liquidity was increased
    /// @param_zh tokenId 增加流动性的 NFT token ID
    /// @param liquidity The amount by which liquidity for the NFT position was increased
    /// @param_zh liquidity 增加的流动性数量
    /// @param amount0 The amount of token0 that was paid for the increase in liquidity
    /// @param_zh amount0 为增加流动性支付的 token0 数量
    /// @param amount1 The amount of token1 that was paid for the increase in liquidity
    /// @param_zh amount1 为增加流动性支付的 token1 数量
    event IncreaseLiquidity(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Emitted when liquidity is decreased for a position NFT
    /// @notice_zh 当位置 NFT 的流动性减少时触发
    /// @param tokenId The ID of the token for which liquidity was decreased
    /// @param_zh tokenId 减少流动性的 NFT token ID
    /// @param liquidity The amount by which liquidity for the NFT position was decreased
    /// @param_zh liquidity 减少的流动性数量
    /// @param amount0 The amount of token0 that was accounted for the decrease in liquidity
    /// @param_zh amount0 减少流动性对应的 token0 数量
    /// @param amount1 The amount of token1 that was accounted for the decrease in liquidity
    /// @param_zh amount1 减少流动性对应的 token1 数量
    event DecreaseLiquidity(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Emitted when tokens are collected for a position NFT
    /// @dev The amounts reported may not be exactly equivalent to the amounts transferred, due to rounding behavior
    /// @notice_zh 当为位置 NFT 收集代币时触发
    /// @dev_zh 由于取整行为，报告的数量可能与实际转移的数量不完全相同
    /// @param tokenId The ID of the token for which underlying tokens were collected
    /// @param_zh tokenId 收取代币的 NFT token ID
    /// @param recipient The address of the account that received the collected tokens
    /// @param_zh recipient 接收收集代币的账户地址
    /// @param amount0 The amount of token0 owed to the position that was collected
    /// @param_zh amount0 收集的 token0 数量
    /// @param amount1 The amount of token1 owed to the position that was collected
    /// @param_zh amount1 收集的 token1 数量
    event Collect(uint256 indexed tokenId, address recipient, uint256 amount0, uint256 amount1);

    /// @notice Returns the position information associated with a given token ID.
    /// @dev Throws if the token ID is not valid.
    /// @notice_zh 返回与给定 token ID 关联的位置信息
    /// @dev_zh 如果 token ID 无效则抛出错误
    /// @param tokenId The ID of the token that represents the position
    /// @param_zh tokenId 代表位置的 NFT token ID
    /// @return nonce The nonce for permits
    /// @return_zh nonce 许可功能的 nonce 值
    /// @return operator The address that is approved for spending
    /// @return_zh operator 被授权操作的地址
    /// @return token0 The address of the token0 for a specific pool
    /// @return_zh token0 池子的第一个代币地址
    /// @return token1 The address of the token1 for a specific pool
    /// @return_zh token1 池子的第二个代币地址
    /// @return fee The fee associated with the pool
    /// @return_zh fee 池子的费用等级
    /// @return tickLower The lower end of the tick range for the position
    /// @return_zh tickLower 价格区间的下限 tick
    /// @return tickUpper The higher end of the tick range for the position
    /// @return_zh tickUpper 价格区间的上限 tick
    /// @return liquidity The liquidity of the position
    /// @return_zh liquidity 位置的流动性数量
    /// @return feeGrowthInside0LastX128 The fee growth of token0 as of the last action on the individual position
    /// @return_zh feeGrowthInside0LastX128 上次操作时 token0 的费用增长累计值（Q128 格式）
    /// @return feeGrowthInside1LastX128 The fee growth of token1 as of the last action on the individual position
    /// @return_zh feeGrowthInside1LastX128 上次操作时 token1 的费用增长累计值（Q128 格式）
    /// @return tokensOwed0 The uncollected amount of token0 owed to the position as of the last computation
    /// @return_zh tokensOwed0 待收集的 token0 数量
    /// @return tokensOwed1 The uncollected amount of token1 owed to the position as of the last computation
    /// @return_zh tokensOwed1 待收集的 token1 数量
    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );

    /// @dev_zh 铸造位置参数结构体
    struct MintParams {
        address token0;           // @dev_zh 第一个代币地址
        address token1;           // @dev_zh 第二个代币地址
        uint24 fee;               // @dev_zh 池子费用等级
        int24 tickLower;          // @dev_zh 价格区间下限
        int24 tickUpper;          // @dev_zh 价格区间上限
        uint256 amount0Desired;   // @dev_zh 期望存入的 token0 数量
        uint256 amount1Desired;   // @dev_zh 期望存入的 token1 数量
        uint256 amount0Min;       // @dev_zh 最少存入 token0 数量（滑点保护）
        uint256 amount1Min;       // @dev_zh 最少存入 token1 数量（滑点保护）
        address recipient;        // @dev_zh NFT 接收地址
        uint256 deadline;         // @dev_zh 交易截止时间
    }

    /// @notice Creates a new position wrapped in a NFT
    /// @dev Call this when the pool does exist and is initialized. Note that if the pool is created but not initialized
    /// a method does not exist, i.e. the pool is assumed to be initialized.
    /// @notice_zh 创建新的流动性位置并铸造 NFT
    /// @dev_zh 在池子存在并已初始化时调用此函数。注意，如果池子已创建但未初始化，该方法不存在，即假设池子已初始化
    /// @param params The params necessary to mint a position, encoded as `MintParams` in calldata
    /// @param_zh params 铸造位置所需的参数，编码为 MintParams 结构体
    /// @return tokenId The ID of the token that represents the minted position
    /// @return_zh tokenId 代表铸造位置的 NFT token ID
    /// @return liquidity The amount of liquidity for this position
    /// @return_zh liquidity 此位置的流动性数量
    /// @return amount0 The amount of token0
    /// @return_zh amount0 实际存入的 token0 数量
    /// @return amount1 The amount of token1
    /// @return_zh amount1 实际存入的 token1 数量
    function mint(MintParams calldata params)
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    /// @dev_zh 增加流动性参数结构体
    struct IncreaseLiquidityParams {
        uint256 tokenId;          // @dev_zh NFT token ID
        uint256 amount0Desired;   // @dev_zh 期望存入的 token0 数量
        uint256 amount1Desired;   // @dev_zh 期望存入的 token1 数量
        uint256 amount0Min;       // @dev_zh 最少存入 token0 数量（滑点保护）
        uint256 amount1Min;       // @dev_zh 最少存入 token1 数量（滑点保护）
        uint256 deadline;         // @dev_zh 交易截止时间
    }

    /// @notice Increases the amount of liquidity in a position, with tokens paid by the `msg.sender`
    /// @notice_zh 为现有位置增加流动性，代币由调用者支付
    /// @param params tokenId The ID of the token for which liquidity is being increased,
    /// amount0Desired The desired amount of token0 to be spent,
    /// amount1Desired The desired amount of token1 to be spent,
    /// amount0Min The minimum amount of token0 to spend, which serves as a slippage check,
    /// amount1Min The minimum amount of token1 to spend, which serves as a slippage check,
    /// deadline The time by which the transaction must be included to effect the change
    /// @param_zh params tokenId 要增加流动性的 NFT token ID，
    /// amount0Desired 期望花费的 token0 数量，
    /// amount1Desired 期望花费的 token1 数量，
    /// amount0Min 最少花费的 token0 数量（滑点检查），
    /// amount1Min 最少花费的 token1 数量（滑点检查），
    /// deadline 交易必须在此时间之前被包含才能生效
    /// @return liquidity The new liquidity amount as a result of the increase
    /// @return_zh liquidity 增加后的新流动性数量
    /// @return amount0 The amount of token0 to acheive resulting liquidity
    /// @return_zh amount0 实现结果流动性所需的 token0 数量
    /// @return amount1 The amount of token1 to acheive resulting liquidity
    /// @return_zh amount1 实现结果流动性所需的 token1 数量
    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        );

    /// @dev_zh 减少流动性参数结构体
    struct DecreaseLiquidityParams {
        uint256 tokenId;          // @dev_zh NFT token ID
        uint128 liquidity;        // @dev_zh 要移除的流动性数量
        uint256 amount0Min;       // @dev_zh 最少收回 token0 数量（滑点保护）
        uint256 amount1Min;       // @dev_zh 最少收回 token1 数量（滑点保护）
        uint256 deadline;         // @dev_zh 交易截止时间
    }

    /// @notice Decreases the amount of liquidity in a position and accounts it to the position
    /// @notice_zh 减少位置中的流动性并计入位置待收款
    /// @param params tokenId The ID of the token for which liquidity is being decreased,
    /// amount The amount by which liquidity will be decreased,
    /// amount0Min The minimum amount of token0 that should be accounted for the burned liquidity,
    /// amount1Min The minimum amount of token1 that should be accounted for the burned liquidity,
    /// deadline The time by which the transaction must be included to effect the change
    /// @param_zh params tokenId 要减少流动性的 NFT token ID，
    /// amount 要减少的流动性数量，
    /// amount0Min 应计入烧毁流动性的最少 token0 数量，
    /// amount1Min 应计入烧毁流动性的最少 token1 数量，
    /// deadline 交易必须在此时间之前被包含才能生效
    /// @return amount0 The amount of token0 accounted to the position's tokens owed
    /// @return_zh amount0 计入位置待收款的 token0 数量
    /// @return amount1 The amount of token1 accounted to the position's tokens owed
    /// @return_zh amount1 计入位置待收款的 token1 数量
    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);

    /// @dev_zh 收集参数结构体
    struct CollectParams {
        uint256 tokenId;          // @dev_zh NFT token ID
        address recipient;        // @dev_zh 接收代币的地址
        uint128 amount0Max;       // @dev_zh 最多收集的 token0 数量
        uint128 amount1Max;       // @dev_zh 最多收集的 token1 数量
    }

    /// @notice Collects up to a maximum amount of fees owed to a specific position to the recipient
    /// @notice_zh 收集位置欠款中的代币到接收地址，最多收集指定数量
    /// @param params tokenId The ID of the NFT for which tokens are being collected,
    /// recipient The account that should receive the tokens,
    /// amount0Max The maximum amount of token0 to collect,
    /// amount1Max The maximum amount of token1 to collect
    /// @param_zh params tokenId 要收集代币的 NFT token ID，
    /// recipient 应接收代币的账户，
    /// amount0Max 最多收集的 token0 数量，
    /// amount1Max 最多收集的 token1 数量
    /// @return amount0 The amount of fees collected in token0
    /// @return_zh amount0 收集到的 token0 费用数量
    /// @return amount1 The amount of fees collected in token1
    /// @return_zh amount1 收集到的 token1 费用数量
    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);

    /// @notice Burns a token ID, which deletes it from the NFT contract. The token must have 0 liquidity and all tokens
    /// must be collected first.
    /// @notice_zh 销毁 NFT token ID，将其从 NFT 合约中删除。NFT 必须流动性为 0 且所有代币必须先被收集
    /// @param tokenId The ID of the token that is being burned
    /// @param_zh tokenId 要销毁的 NFT token ID
    function burn(uint256 tokenId) external payable;
}
