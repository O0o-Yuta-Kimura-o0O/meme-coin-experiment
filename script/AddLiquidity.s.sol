// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address);
}

interface IUniswapV3Pool {
    function slot0()
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint16, uint16, uint16, uint8, bool);
}

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function createAndInitializePoolIfNecessary(address token0, address token1, uint24 fee, uint160 sqrtPriceX96)
        external
        payable
        returns (address pool);

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

interface IWETH is IERC20 {
    function deposit() external payable;
}

/// @notice Uniswap v3（手数料 1%、tickSpacing 200）にプールを作り、流動性を入れる。2つの方式がある。
///         - single（片側流動性）：ETH を入れず、トークンだけを「開始価格より上」の全範囲に置く。
///           買われるほど価格が上がり ETH がたまる。価格は開始価格より下がらない。
///           価格帯（TICK_LOWER / TICK_UPPER）と初期価格は script/liquidity_params.py が開始時の FDV から計算する。
///         - full（両側・フルレンジ）：トークンと ETH を両方入れる。初期価格 = 入れる ETH ÷ 入れるトークン量。
///         どちらも、誰かが先に別の価格でプールを作っていた場合（先回り攻撃）は中止する。
///         設定値は deploy.sh と同じく coins/<コイン名>/coin.env から add-liquidity.sh 経由で渡される。
contract AddLiquidity is Script {
    uint24 public constant FEE = 10_000;
    int24 public constant TICK_LOWER = -887_200;
    int24 public constant TICK_UPPER = 887_200;
    address public constant WETH = 0x4200000000000000000000000000000000000006;

    struct Uniswap {
        IUniswapV3Factory factory;
        INonfungiblePositionManager positionManager;
    }

    struct Result {
        address pool;
        uint256 tokenId;
        uint128 liquidity;
        uint256 tokenUsed;
        uint256 ethUsed;
    }

    /// @notice チェーン ID ごとの Uniswap v3 のアドレス（Uniswap 公式ドキュメントより）
    function uniswapFor(uint256 chainId) public pure returns (Uniswap memory u) {
        if (chainId == 8453) {
            u.factory = IUniswapV3Factory(0x33128a8fC17869897dcE68Ed026d694621f6FDfD);
            u.positionManager = INonfungiblePositionManager(0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1);
        } else if (chainId == 84532) {
            u.factory = IUniswapV3Factory(0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24);
            u.positionManager = INonfungiblePositionManager(0x27F971cb582BF9E50F397e4d29a5C7A34f11faA2);
        } else {
            revert("unsupported chain (Base 8453 / Base Sepolia 84532 only)");
        }
    }

    function run() external {
        address token = vm.envAddress("TOKEN_ADDRESS");
        address recipient = vm.envOr("LP_RECIPIENT", address(0));
        bool single = keccak256(bytes(vm.envOr("LIQUIDITY_MODE", string("full")))) == keccak256("single");

        vm.startBroadcast();
        if (recipient == address(0)) recipient = msg.sender;
        uint256 tokenAmount = IERC20(token).balanceOf(msg.sender);
        Result memory r = single
            ? addSingleSided(
                SingleSided({
                    token: token,
                    tokenAmount: tokenAmount,
                    tickLower: int24(vm.envInt("TICK_LOWER")),
                    tickUpper: int24(vm.envInt("TICK_UPPER")),
                    initSqrtPriceX96: uint160(vm.envUint("INIT_SQRT_PRICE_X96")),
                    recipient: recipient
                })
            )
            : addLiquidity(token, tokenAmount, vm.envUint("LIQUIDITY_ETH_WEI"), recipient);
        vm.stopBroadcast();

        console2.log("Mode           :", single ? "single-sided (token only)" : "full range (token + ETH)");
        console2.log("Pool           :", r.pool);
        console2.log("LP NFT tokenId :", r.tokenId);
        console2.log("LP recipient   :", recipient);
        console2.log("Token used     :", r.tokenUsed / 1e18);
        console2.log("ETH used (wei) :", r.ethUsed);
    }

    struct SingleSided {
        address token;
        uint256 tokenAmount;
        int24 tickLower;
        int24 tickUpper;
        uint160 initSqrtPriceX96;
        address recipient;
    }

    /// @notice 片側流動性：トークンだけで、開始価格より上（トークンが高くなる側）の全範囲にプールを作る
    function addSingleSided(SingleSided memory p) public returns (Result memory r) {
        require(p.tokenAmount > 0, "amount must be > 0");
        require(
            p.tickLower < p.tickUpper && p.tickLower % 200 == 0 && p.tickUpper % 200 == 0, "bad tick range"
        );
        Uniswap memory u = uniswapFor(block.chainid);
        bool tokenIs0 = p.token < WETH;
        (address token0, address token1) = tokenIs0 ? (p.token, WETH) : (WETH, p.token);

        _checkNotFrontRun(u, token0, token1, p.initSqrtPriceX96);
        r.pool = u.positionManager.createAndInitializePoolIfNecessary(token0, token1, FEE, p.initSqrtPriceX96);

        // 範囲が現在価格の片側にあることを確かめる（トークンだけで入るはず）
        (, int24 tick,,,,,) = IUniswapV3Pool(r.pool).slot0();
        require(tokenIs0 ? tick < p.tickLower : tick >= p.tickUpper, "range must be on the token side of the price");

        IERC20(p.token).approve(address(u.positionManager), p.tokenAmount);
        uint256 used0;
        uint256 used1;
        (r.tokenId, r.liquidity, used0, used1) = u.positionManager.mint(_singleSidedMint(p, token0, token1, tokenIs0));
        (r.tokenUsed, r.ethUsed) = tokenIs0 ? (used0, used1) : (used1, used0);
    }

    function _singleSidedMint(SingleSided memory p, address token0, address token1, bool tokenIs0)
        internal
        view
        returns (INonfungiblePositionManager.MintParams memory m)
    {
        m.token0 = token0;
        m.token1 = token1;
        m.fee = FEE;
        m.tickLower = p.tickLower;
        m.tickUpper = p.tickUpper;
        if (tokenIs0) {
            m.amount0Desired = p.tokenAmount;
            m.amount0Min = p.tokenAmount * 99 / 100;
        } else {
            m.amount1Desired = p.tokenAmount;
            m.amount1Min = p.tokenAmount * 99 / 100;
        }
        m.recipient = p.recipient;
        m.deadline = block.timestamp + 600;
    }

    /// @notice 先回り対策：既に誰かがプールを作っていたら、価格が想定の ±1% 以内でなければ中止
    function _checkNotFrontRun(Uniswap memory u, address token0, address token1, uint160 sqrtPriceX96) internal view {
        address existing = u.factory.getPool(token0, token1, FEE);
        if (existing == address(0)) return;
        (uint160 current,,,,,,) = IUniswapV3Pool(existing).slot0();
        if (current == 0) return;
        uint256 diff = current > sqrtPriceX96 ? current - sqrtPriceX96 : sqrtPriceX96 - current;
        require(diff * 200 <= sqrtPriceX96, "pool already initialized at a different price");
    }

    /// @notice 両側・フルレンジ：呼び出し元（broadcast 中はデプロイしたウォレット）が持つトークンと ETH でプールを作る
    function addLiquidity(address token, uint256 tokenAmount, uint256 ethAmount, address recipient)
        public
        returns (Result memory r)
    {
        require(tokenAmount > 0 && ethAmount > 0, "amounts must be > 0");
        Uniswap memory u = uniswapFor(block.chainid);

        (address token0, address token1) = token < WETH ? (token, WETH) : (WETH, token);
        (uint256 amount0, uint256 amount1) = token0 == token ? (tokenAmount, ethAmount) : (ethAmount, tokenAmount);

        // price = amount1 / amount0、sqrtPriceX96 = sqrt(price) * 2^96
        uint160 sqrtPriceX96 = uint160(Math.sqrt(Math.mulDiv(amount1, 1 << 192, amount0)));

        _checkNotFrontRun(u, token0, token1, sqrtPriceX96);

        r.pool = u.positionManager.createAndInitializePoolIfNecessary(token0, token1, FEE, sqrtPriceX96);

        IWETH(WETH).deposit{value: ethAmount}();
        IERC20(WETH).approve(address(u.positionManager), ethAmount);
        IERC20(token).approve(address(u.positionManager), tokenAmount);

        uint256 used0;
        uint256 used1;
        (r.tokenId, r.liquidity, used0, used1) = u.positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: FEE,
                tickLower: TICK_LOWER,
                tickUpper: TICK_UPPER,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: amount0 * 99 / 100,
                amount1Min: amount1 * 99 / 100,
                recipient: recipient,
                deadline: block.timestamp + 600
            })
        );
        (r.tokenUsed, r.ethUsed) = token0 == token ? (used0, used1) : (used1, used0);
    }
}
