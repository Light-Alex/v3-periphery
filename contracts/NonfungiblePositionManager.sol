// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

// V3 核心接口 - 池子接口
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
// V3 核心库 - 定点数学运算（Q128 格式）
import '@uniswap/v3-core/contracts/libraries/FixedPoint128.sol';
// V3 核心库 - 完整数学运算（避免溢出）
import '@uniswap/v3-core/contracts/libraries/FullMath.sol';

// 本项目接口 - NFT 位置管理器接口
import './interfaces/INonfungiblePositionManager.sol';
// 本项目接口 - NFT 描述符接口
import './interfaces/INonfungibleTokenPositionDescriptor.sol';
// 库文件 - 位置密钥计算
import './libraries/PositionKey.sol';
// 库文件 - 池地址计算
import './libraries/PoolAddress.sol';
// 基础合约 - 流动性管理
import './base/LiquidityManagement.sol';
// 基础合约 - 不可变状态
import './base/PeripheryImmutableState.sol';
// 基础合约 - 多重调用
import './base/Multicall.sol';
// 基础合约 - ERC721 许可
import './base/ERC721Permit.sol';
// 基础合约 - 验证功能
import './base/PeripheryValidation.sol';
// 基础合约 - 自许可
import './base/SelfPermit.sol';
// 基础合约 - 池初始化
import './base/PoolInitializer.sol';

/// @title NFT positions
/// @notice Wraps Uniswap V3 positions in the ERC721 non-fungible token interface
/// @notice_zh NFT 位置管理器 - 将 Uniswap V3 流动性位置包装为 ERC721 非同质化代币
/// @dev_zh 此合约是流动性提供者的核心接口，每个流动性位置对应一个唯一的 NFT
/// @dev_zh 用户可以创建、增加、减少流动性，并收集交易费用，所有操作都通过 NFT 进行
contract NonfungiblePositionManager is
    INonfungiblePositionManager,
    Multicall,
    ERC721Permit,
    PeripheryImmutableState,
    PoolInitializer,
    LiquidityManagement,
    PeripheryValidation,
    SelfPermit
{
    // details about the uniswap position
    /// @dev_zh Position 结构体 - 存储流动性位置的所有信息
    struct Position {
        // the nonce for permits
        uint96 nonce;  // @dev_zh 许可功能的 nonce 值，用于签名授权
        // the address that is approved for spending this token
        address operator;  // @dev_zh 被授权操作此 NFT 的地址（除所有者外）
        // the ID of the pool with which this token is connected
        uint80 poolId;  // @dev_zh 此位置所属池子的 ID
        // the tick range of the position
        int24 tickLower;  // @dev_zh 价格区间的下限 tick
        int24 tickUpper;  // @dev_zh 价格区间的上限 tick
        // the liquidity of the position
        uint128 liquidity;  // @dev_zh 位置的流动性数量
        // the fee growth of the aggregate position as of the last action on the individual position
        uint256 feeGrowthInside0LastX128;  // @dev_zh 上次操作时 token0 的费用增长累计值（Q128 格式）
        uint256 feeGrowthInside1LastX128;  // @dev_zh 上次操作时 token1 的费用增长累计值（Q128 格式）
        // how many uncollected tokens are owed to the position, as of the last computation
        uint128 tokensOwed0;  // @dev_zh 待收集的 token0 数量: 本金+交易手续费（不包括协议手续费）
        uint128 tokensOwed1;  // @dev_zh 待收集的 token1 数量: 本金+交易手续费（不包括协议手续费）
    }

    /// @dev IDs of pools assigned by this contract
    /// @dev_zh 池子地址到池子 ID 的映射，节省存储空间
    mapping(address => uint80) private _poolIds;

    /// @dev Pool keys by pool ID, to save on SSTOREs for position data
    /// @dev_zh 池子 ID 到池子密钥的映射，避免在位置数据中重复存储代币地址和费用
    mapping(uint80 => PoolAddress.PoolKey) private _poolIdToPoolKey;

    /// @dev The token ID position data
    /// @dev_zh NFT token ID 到位置数据的映射
    mapping(uint256 => Position) private _positions;

    /// @dev The ID of the next token that will be minted. Skips 0
    /// @dev_zh 下一个要铸造的 NFT token ID，从 1 开始（跳过 0）
    uint176 private _nextId = 1;
    /// @dev The ID of the next pool that is used for the first time. Skips 0
    /// @dev_zh 下一个首次使用的池子 ID，从 1 开始（跳过 0）
    uint80 private _nextPoolId = 1;

    /// @dev The address of the token descriptor contract, which handles generating token URIs for position tokens
    /// @dev_zh NFT 描述符合约地址，负责生成 NFT 的 tokenURI（元数据）
    address private immutable _tokenDescriptor;

    /// @notice_zh 构造函数 - 初始化合约参数
    /// @param _factory Uniswap V3 Factory 合约地址
    /// @param _WETH9 WETH9 合约地址
    /// @param _tokenDescriptor_ NFT 描述符合约地址
    constructor(
        address _factory,
        address _WETH9,
        address _tokenDescriptor_
    ) ERC721Permit('Uniswap V3 Positions NFT-V1', 'UNI-V3-POS', '1') PeripheryImmutableState(_factory, _WETH9) {
        _tokenDescriptor = _tokenDescriptor_;
    }

    /// @inheritdoc INonfungiblePositionManager
    /// @notice_zh 获取 NFT 位置的详细信息
    /// @param tokenId NFT token ID
    /// @return nonce 许可 nonce 值
    /// @return operator 被授权的操作员地址
    /// @return token0 池子的第一个代币地址
    /// @return token1 池子的第二个代币地址
    /// @return fee 池子费用等级
    /// @return tickLower 价格区间下限
    /// @return tickUpper 价格区间上限
    /// @return liquidity 流动性数量
    /// @return feeGrowthInside0LastX128 token0 费用增长累计值
    /// @return feeGrowthInside1LastX128 token1 费用增长累计值
    /// @return tokensOwed0 待收集的 token0 数量
    /// @return tokensOwed1 待收集的 token1 数量
    /// 注意: tokensOwed记录了以下内容的累计：
    /// 交易费用 - 流动性提供者赚取的交易手续费
    /// 移除流动性时的本金 - 当调用 decreaseLiquidity 时，移除的代币不会直接发送给用户，而是先累积到这里
    function positions(uint256 tokenId)
        external
        view
        override
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
        )
    {
        // @dev_zh 从映射中获取位置数据
        Position memory position = _positions[tokenId];
        // @dev_zh 检查 token ID 是否有效（poolId 不为 0）
        require(position.poolId != 0, 'Invalid token ID');
        // @dev_zh 根据 poolId 获取池子密钥
        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];
        return (
            position.nonce,
            position.operator,
            poolKey.token0,
            poolKey.token1,
            poolKey.fee,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            position.feeGrowthInside0LastX128,
            position.feeGrowthInside1LastX128,
            position.tokensOwed0,
            position.tokensOwed1
        );
    }

    /// @dev Caches a pool key
    /// @dev_zh 缓存池子密钥 - 如果池子首次使用则分配新 ID
    /// @param pool 池子地址
    /// @param poolKey 池子密钥（包含代币地址和费用）
    /// @return poolId 池子 ID
    function cachePoolKey(address pool, PoolAddress.PoolKey memory poolKey) private returns (uint80 poolId) {
        poolId = _poolIds[pool];
        // @dev_zh 如果池子首次使用，分配新 ID 并存储密钥
        if (poolId == 0) {
            _poolIds[pool] = (poolId = _nextPoolId++);
            _poolIdToPoolKey[poolId] = poolKey;
        }
    }

    /// @inheritdoc INonfungiblePositionManager
    /// @notice_zh 创建新的流动性位置并铸造 NFT
    /// @dev_zh 此函数用于首次提供流动性，会创建一个新的 NFT 代表该流动性位置
    /// @param params 铸造参数，包含：
    ///   - token0/token1: 代币地址
    ///   - fee: 池子费用等级
    ///   - tickLower/tickUpper: 价格区间
    ///   - amount0Desired/amount1Desired: 期望存入的代币数量
    ///   - amount0Min/amount1Min: 最少存入数量（滑点保护）
    ///   - recipient: NFT 接收地址
    ///   - deadline: 交易截止时间
    /// @return tokenId 新铸造的 NFT token ID
    /// @return liquidity 实际创建的流动性数量
    /// @return amount0 实际存入的 token0 数量
    /// @return amount1 实际存入的 token1 数量
    function mint(MintParams calldata params)
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        IUniswapV3Pool pool;
        // @dev_zh 调用 addLiquidity 函数添加流动性
        (liquidity, amount0, amount1, pool) = addLiquidity(
            AddLiquidityParams({
                token0: params.token0,
                token1: params.token1,
                fee: params.fee,
                recipient: address(this),  // @dev_zh 流动性暂时添加到此合约
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                amount0Desired: params.amount0Desired,
                amount1Desired: params.amount1Desired,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min
            })
        );

        // @dev_zh 铸造 NFT 给接收者
        _mint(params.recipient, (tokenId = _nextId++));

        // @dev_zh 计算位置密钥并获取池子中的费用增长数据
        bytes32 positionKey = PositionKey.compute(address(this), params.tickLower, params.tickUpper);
        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) = pool.positions(positionKey);

        // idempotent set
        // @dev_zh 缓存池子密钥（幂等操作）
        uint80 poolId =
            cachePoolKey(
                address(pool),
                PoolAddress.PoolKey({token0: params.token0, token1: params.token1, fee: params.fee})
            );

        // @dev_zh 创建并存储位置数据
        _positions[tokenId] = Position({
            nonce: 0,
            operator: address(0),
            poolId: poolId,
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            liquidity: liquidity,
            feeGrowthInside0LastX128: feeGrowthInside0LastX128,
            feeGrowthInside1LastX128: feeGrowthInside1LastX128,
            tokensOwed0: 0,
            tokensOwed1: 0
        });

        // @dev_zh 触发流动性增加事件
        emit IncreaseLiquidity(tokenId, liquidity, amount0, amount1);
    }

    /// @dev_zh 修饰符：检查调用者是否有权操作指定的 NFT
    /// @param tokenId NFT token ID
    /// @dev_zh 只有 NFT 的所有者或被授权者才能调用带此修饰符的函数
    modifier isAuthorizedForToken(uint256 tokenId) {
        require(_isApprovedOrOwner(msg.sender, tokenId), 'Not approved');
        _;
    }

    /// @notice_zh 获取 NFT 的元数据 URI
    /// @dev_zh 此函数返回描述 NFT 的 URI，包含位置信息的 JSON 元数据
    /// @param tokenId NFT token ID
    /// @return NFT 的 tokenURI 字符串
    function tokenURI(uint256 tokenId) public view override(ERC721, IERC721Metadata) returns (string memory) {
        require(_exists(tokenId));
        // @dev_zh 委托给描述符合约生成 URI
        return INonfungibleTokenPositionDescriptor(_tokenDescriptor).tokenURI(this, tokenId);
    }

    // save bytecode by removing implementation of unused method
    /// @dev_zh 保存字节码 - 移除未使用方法的实现
    function baseURI() public pure override returns (string memory) {}

    /// @inheritdoc INonfungiblePositionManager
    /// @notice_zh 为现有流动性位置增加流动性
    /// @dev_zh 此函数用于向已有的 NFT 位置添加更多流动性，价格区间不变
    /// @param params 增加流动性参数，包含：
    ///   - tokenId: NFT token ID
    ///   - amount0Desired/amount1Desired: 期望存入的代币数量
    ///   - amount0Min/amount1Min: 最少存入数量（滑点保护）
    ///   - deadline: 交易截止时间
    /// @return liquidity 新增的流动性数量
    /// @return amount0 实际存入的 token0 数量
    /// @return amount1 实际存入的 token1 数量
    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        override
        checkDeadline(params.deadline)
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        // @dev_zh 获取位置数据
        Position storage position = _positions[params.tokenId];

        // @dev_zh 获取池子信息
        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];

        IUniswapV3Pool pool;
        // @dev_zh 调用 addLiquidity 添加流动性
        (liquidity, amount0, amount1, pool) = addLiquidity(
            AddLiquidityParams({
                token0: poolKey.token0,
                token1: poolKey.token1,
                fee: poolKey.fee,
                tickLower: position.tickLower,
                tickUpper: position.tickUpper,
                amount0Desired: params.amount0Desired,
                amount1Desired: params.amount1Desired,
                amount0Min: params.amount0Min,
                amount1Min: params.amount1Min,
                recipient: address(this)
            })
        );

        // @dev_zh 计算位置密钥
        bytes32 positionKey = PositionKey.compute(address(this), position.tickLower, position.tickUpper);

        // this is now updated to the current transaction
        // @dev_zh 获取当前最新的费用增长数据
        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) = pool.positions(positionKey);

        // @dev_zh 计算并累积新增的待收取费用（token0）
        position.tokensOwed0 += uint128(
            FullMath.mulDiv(
                feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128,
                position.liquidity,
                FixedPoint128.Q128
            )
        );
        // @dev_zh 计算并累积新增的待收取费用（token1）
        position.tokensOwed1 += uint128(
            FullMath.mulDiv(
                feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128,
                position.liquidity,
                FixedPoint128.Q128
            )
        );

        // @dev_zh 更新费用增长快照
        position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
        position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
        // @dev_zh 增加流动性数量
        position.liquidity += liquidity;

        // @dev_zh 触发事件
        emit IncreaseLiquidity(params.tokenId, liquidity, amount0, amount1);
    }

    /// @inheritdoc INonfungiblePositionManager
    /// @notice_zh 减少流动性位置中的流动性
    /// @dev_zh 此函数用于移除流动性，代币会累积到 tokensOwed 中，需要调用 collect 才能收到
    /// @param params 减少流动性参数，包含：
    ///   - tokenId: NFT token ID
    ///   - liquidity: 要移除的流动性数量
    ///   - amount0Min/amount1Min: 最少收回数量（滑点保护）
    ///   - deadline: 交易截止时间
    /// @return amount0 收回的 token0 数量
    /// @return amount1 收回的 token1 数量
    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        override
        isAuthorizedForToken(params.tokenId)
        checkDeadline(params.deadline)
        returns (uint256 amount0, uint256 amount1)
    {
        // @dev_zh 要求移除的流动性大于 0
        require(params.liquidity > 0);
        Position storage position = _positions[params.tokenId];

        // @dev_zh 获取当前位置的流动性
        uint128 positionLiquidity = position.liquidity;
        // @dev_zh 检查流动性是否足够
        require(positionLiquidity >= params.liquidity);

        // @dev_zh 获取池子地址
        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];
        IUniswapV3Pool pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey));
        // @dev_zh 调用池子的 burn 函数移除流动性
        (amount0, amount1) = pool.burn(position.tickLower, position.tickUpper, params.liquidity);

        // @dev_zh 滑点检查：确保收回的代币数量满足最小值要求
        require(amount0 >= params.amount0Min && amount1 >= params.amount1Min, 'Price slippage check');

        // @dev_zh 计算位置密钥
        bytes32 positionKey = PositionKey.compute(address(this), position.tickLower, position.tickUpper);
        // this is now updated to the current transaction
        // @dev_zh 获取最新的费用增长数据
        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) = pool.positions(positionKey);

        // @dev_zh 累积待收取的 token0（收回的本金 + 新增费用）
        position.tokensOwed0 +=
            uint128(amount0) +
            uint128(
                FullMath.mulDiv(
                    feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128,
                    positionLiquidity,
                    FixedPoint128.Q128
                )
            );
        // @dev_zh 累积待收取的 token1（收回的本金 + 新增费用）
        position.tokensOwed1 +=
            uint128(amount1) +
            uint128(
                FullMath.mulDiv(
                    feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128,
                    positionLiquidity,
                    FixedPoint128.Q128
                )
            );

        // @dev_zh 更新费用增长快照
        position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
        position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
        // subtraction is safe because we checked positionLiquidity is gte params.liquidity
        // @dev_zh 减少流动性数量（减法是安全的，因为我们已经检查过）
        position.liquidity = positionLiquidity - params.liquidity;

        // @dev_zh 触发事件
        emit DecreaseLiquidity(params.tokenId, params.liquidity, amount0, amount1);
    }

    /// @inheritdoc INonfungiblePositionManager
    /// @notice_zh 收集流动性位置的费用和代币
    /// @dev_zh 此函数用于收集 tokensOwed 中累积的代币（包括减少流动性时的本金和交易费用(不包括协议手续费)）
    /// @param params 收集参数，包含：
    ///   - tokenId: NFT token ID
    ///   - recipient: 接收代币的地址（address(0) 表示发送到此合约）
    ///   - amount0Max: 最多收集的 token0 数量（type(uint128).max 表示全部）
    ///   - amount1Max: 最多收集的 token1 数量（type(uint128).max 表示全部）
    /// @return amount0 实际收集的 token0 数量
    /// @return amount1 实际收集的 token1 数量
    function collect(CollectParams calldata params)
        external
        payable
        override
        isAuthorizedForToken(params.tokenId)
        returns (uint256 amount0, uint256 amount1)
    {
        // @dev_zh 要求至少要收集一种代币
        require(params.amount0Max > 0 || params.amount1Max > 0);
        // allow collecting to the nft position manager address with address 0
        // @dev_zh 允许收集到 NFT 位置管理器地址（使用 address(0）
        address recipient = params.recipient == address(0) ? address(this) : params.recipient;

        // @dev_zh 获取位置数据
        Position storage position = _positions[params.tokenId];

        // @dev_zh 获取池子信息
        PoolAddress.PoolKey memory poolKey = _poolIdToPoolKey[position.poolId];

        // @dev_zh 获取池子地址
        IUniswapV3Pool pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey));

        // @dev_zh 获取当前待收取的代币数量
        (uint128 tokensOwed0, uint128 tokensOwed1) = (position.tokensOwed0, position.tokensOwed1);

        // trigger an update of the position fees owed and fee growth snapshots if it has any liquidity
        // @dev_zh 如果位置还有流动性，触发更新待收取费用和费用增长快照
        if (position.liquidity > 0) {
            // @dev_zh 调用 burn(0) 来更新费用
            // 更新的是池子合约内部的 positions 映射
            pool.burn(position.tickLower, position.tickUpper, 0);
            // 从池子读取更新后的值
            (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) =
                pool.positions(PositionKey.compute(address(this), position.tickLower, position.tickUpper));

            // @dev_zh 计算并累积新的待收取费用（token0）
            // position.feeGrowthInside0LastX128是NFT合约本地存储的快照
            tokensOwed0 += uint128(
                FullMath.mulDiv(
                    // 池子中的最新值 - NFT 合约中的旧快照
                    feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128,
                    position.liquidity,
                    FixedPoint128.Q128
                )
            );
            // @dev_zh 计算并累积新的待收取费用（token1）
            tokensOwed1 += uint128(
                FullMath.mulDiv(
                    feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128,
                    position.liquidity,
                    FixedPoint128.Q128
                )
            );

            // @dev_zh 更新费用增长快照
            position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
            position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
        }

        // compute the arguments to give to the pool#collect method
        // @dev_zh 计算实际要收集的数量（取最小值）
        (uint128 amount0Collect, uint128 amount1Collect) =
            (
                params.amount0Max > tokensOwed0 ? tokensOwed0 : params.amount0Max,
                params.amount1Max > tokensOwed1 ? tokensOwed1 : params.amount1Max
            );

        // the actual amounts collected are returned
        // @dev_zh 调用池子的 collect 函数执行收集
        (amount0, amount1) = pool.collect(
            recipient,
            position.tickLower,
            position.tickUpper,
            amount0Collect,
            amount1Collect
        );

        // sometimes there will be a few less wei than expected due to rounding down in core, but we just subtract the full amount expected
        // instead of the actual amount so we can burn the token
        // @dev_zh 更新待收取数量（有时由于核心合约的向下取整，实际收集的会略少于预期，但我们减去预期数量以便销毁代币）
        (position.tokensOwed0, position.tokensOwed1) = (tokensOwed0 - amount0Collect, tokensOwed1 - amount1Collect);

        // @dev_zh 触发事件
        emit Collect(params.tokenId, recipient, amount0Collect, amount1Collect);
    }

    /// @inheritdoc INonfungiblePositionManager
    /// @notice_zh 销毁 NFT 位置
    /// @dev_zh 此函数用于永久销毁流动性位置 NFT，只能在流动性为 0 且所有费用都已收集后调用
    /// @param tokenId 要销毁的 NFT token ID
    function burn(uint256 tokenId) external payable override isAuthorizedForToken(tokenId) {
        Position storage position = _positions[tokenId];
        // @dev_zh 检查位置是否已清空（流动性为 0 且无待收取代币）
        require(position.liquidity == 0 && position.tokensOwed0 == 0 && position.tokensOwed1 == 0, 'Not cleared');
        // @dev_zh 删除位置数据
        delete _positions[tokenId];
        // @dev_zh 销毁 NFT
        _burn(tokenId);
    }

    /// @notice_zh 获取并增加许可 nonce
    /// @dev_zh 此函数用于 permit 功能，每次调用会增加位置的 nonce 值
    /// @param tokenId NFT token ID
    /// @return 当前的 nonce 值（增加前）
    function _getAndIncrementNonce(uint256 tokenId) internal override returns (uint256) {
        return uint256(_positions[tokenId].nonce++);
    }

    /// @inheritdoc IERC721
    /// @notice_zh 获取 NFT 的被授权者地址
    /// @dev_zh 返回被授权操作此 NFT 的地址（所有者除外）
    /// @param tokenId NFT token ID
    /// @return 被授权者的地址
    function getApproved(uint256 tokenId) public view override(ERC721, IERC721) returns (address) {
        require(_exists(tokenId), 'ERC721: approved query for nonexistent token');

        // @dev_zh 返回位置数据中存储的操作员地址
        return _positions[tokenId].operator;
    }

    /// @dev Overrides _approve to use the operator in the position, which is packed with the position permit nonce
    /// @dev_zh 重写 _approve 函数，使用位置数据中的 operator 字段
    /// @dev_zh 这样可以节省 gas，因为 operator 和 nonce 打包在一起存储
    /// @param to 被授权的地址
    /// @param tokenId NFT token ID
    function _approve(address to, uint256 tokenId) internal override(ERC721) {
        _positions[tokenId].operator = to;
        emit Approval(ownerOf(tokenId), to, tokenId);
    }
}
