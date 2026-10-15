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
///         受取人（LP_RECIPIENTS、カンマ区切り）が複数なら、量を人数で均等に分け、同じ価格帯のポジション（NFT）を
///         人数分作る。量と価格帯が同じなので、買い手が払う ETH も取引手数料も、取引のたびに均等に分かれてたまる。
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
        uint256[] tokenIds;
        uint128[] liquidities;
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
        bool single = keccak256(bytes(vm.envOr("LIQUIDITY_MODE", string("full")))) == keccak256("single");

        vm.startBroadcast();
        (, address sender,) = vm.readCallers();
        address[] memory recipients = _recipients(sender);
        uint256 tokenAmount = IERC20(token).balanceOf(sender);
        Result memory r = single
            ? addSingleSided(
                SingleSided({
                    token: token,
                    tokenAmount: tokenAmount,
                    tickLower: int24(vm.envInt("TICK_LOWER")),
                    tickUpper: int24(vm.envInt("TICK_UPPER")),
                    initSqrtPriceX96: uint160(vm.envUint("INIT_SQRT_PRICE_X96")),
                    recipients: recipients
                })
            )
            : addLiquidity(token, tokenAmount, vm.envUint("LIQUIDITY_ETH_WEI"), recipients);
        vm.stopBroadcast();

        console2.log("Mode           :", single ? "single-sided (token only)" : "full range (token + ETH)");
        console2.log("Pool           :", r.pool);
        for (uint256 i; i < r.tokenIds.length; i++) {
            console2.log("LP NFT (simulated id):", r.tokenIds[i], "-> owner", recipients[i]);
        }
        console2.log("Token used     :", r.tokenUsed / 1e18);
        console2.log("ETH used (wei) :", r.ethUsed);
    }

    /// @notice LP_RECIPIENTS（カンマ区切り）→ LP_RECIPIENT（1人）→ デプロイしたウォレット、の順に使う
    function _recipients(address sender) internal view returns (address[] memory list) {
        list = vm.envOr("LP_RECIPIENTS", ",", new address[](0));
        if (list.length > 0) return list;
        list = new address[](1);
        list[0] = vm.envOr("LP_RECIPIENT", address(0));
        if (list[0] == address(0)) list[0] = sender;
    }

    /// @notice total を n 人で均等に分けたときの i 番目の量（端数は最初の一人に足す）
    function _share(uint256 total, uint256 n, uint256 i) internal pure returns (uint256) {
        return total / n + (i == 0 ? total % n : 0);
    }

    /// @notice ポジションを 1 つ作り、結果を r の i 番目に書き込む
    function _mintInto(
        Result memory r,
        uint256 i,
        INonfungiblePositionManager pm,
        INonfungiblePositionManager.MintParams memory m,
        bool tokenIs0
    ) internal {
        (uint256 id, uint128 liq, uint256 used0, uint256 used1) = pm.mint(m);
        r.tokenIds[i] = id;
        r.liquidities[i] = liq;
        r.tokenUsed += tokenIs0 ? used0 : used1;
        r.ethUsed += tokenIs0 ? used1 : used0;
    }

    struct SingleSided {
        address token;
        uint256 tokenAmount;
        int24 tickLower;
        int24 tickUpper;
        uint160 initSqrtPriceX96;
        address[] recipients;
    }

    /// @notice 片側流動性：トークンだけで、開始価格より上（トークンが高くなる側）の全範囲にプールを作る
    function addSingleSided(SingleSided memory p) public returns (Result memory r) {
        require(p.tokenAmount > 0, "amount must be > 0");
        require(p.recipients.length > 0, "no LP recipients");
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
        _mintSingleSidedAll(r, u.positionManager, p, Pair(token0, token1, 0, 0, tokenIs0));
    }

    function _mintSingleSidedAll(Result memory r, INonfungiblePositionManager pm, SingleSided memory p, Pair memory q)
        internal
    {
        uint256 n = p.recipients.length;
        r.tokenIds = new uint256[](n);
        r.liquidities = new uint128[](n);
        for (uint256 i; i < n; i++) {
            _mintInto(r, i, pm, _singleSidedMint(p, _share(p.tokenAmount, n, i), p.recipients[i], q), q.tokenIs0);
        }
    }

    function _singleSidedMint(SingleSided memory p, uint256 amount, address recipient, Pair memory q)
        internal
        view
        returns (INonfungiblePositionManager.MintParams memory m)
    {
        m.token0 = q.token0;
        m.token1 = q.token1;
        m.fee = FEE;
        m.tickLower = p.tickLower;
        m.tickUpper = p.tickUpper;
        if (q.tokenIs0) {
            m.amount0Desired = amount;
            m.amount0Min = amount * 99 / 100;
        } else {
            m.amount1Desired = amount;
            m.amount1Min = amount * 99 / 100;
        }
        m.recipient = recipient;
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

    /// @notice トークンと WETH の並び順と、それぞれの量
    struct Pair {
        address token0;
        address token1;
        uint256 amount0;
        uint256 amount1;
        bool tokenIs0;
    }

    /// @notice 両側・フルレンジ：呼び出し元（broadcast 中はデプロイしたウォレット）が持つトークンと ETH でプールを作る
    function addLiquidity(address token, uint256 tokenAmount, uint256 ethAmount, address[] memory recipients)
        public
        returns (Result memory r)
    {
        require(tokenAmount > 0 && ethAmount > 0, "amounts must be > 0");
        require(recipients.length > 0, "no LP recipients");
        Uniswap memory u = uniswapFor(block.chainid);
        Pair memory q = token < WETH
            ? Pair(token, WETH, tokenAmount, ethAmount, true)
            : Pair(WETH, token, ethAmount, tokenAmount, false);

        // price = amount1 / amount0、sqrtPriceX96 = sqrt(price) * 2^96
        uint160 sqrtPriceX96 = uint160(Math.sqrt(Math.mulDiv(q.amount1, 1 << 192, q.amount0)));
        _checkNotFrontRun(u, q.token0, q.token1, sqrtPriceX96);
        r.pool = u.positionManager.createAndInitializePoolIfNecessary(q.token0, q.token1, FEE, sqrtPriceX96);

        IWETH(WETH).deposit{value: ethAmount}();
        IERC20(WETH).approve(address(u.positionManager), ethAmount);
        IERC20(token).approve(address(u.positionManager), tokenAmount);
        _mintFullRangeAll(r, u.positionManager, q, recipients);
    }

    function _mintFullRangeAll(
        Result memory r,
        INonfungiblePositionManager pm,
        Pair memory q,
        address[] memory recipients
    ) internal {
        uint256 n = recipients.length;
        r.tokenIds = new uint256[](n);
        r.liquidities = new uint128[](n);
        for (uint256 i; i < n; i++) {
            _mintInto(
                r,
                i,
                pm,
                _fullRangeMint(q.token0, q.token1, _share(q.amount0, n, i), _share(q.amount1, n, i), recipients[i]),
                q.tokenIs0
            );
        }
    }

    function _fullRangeMint(address token0, address token1, uint256 amount0, uint256 amount1, address recipient)
        internal
        view
        returns (INonfungiblePositionManager.MintParams memory)
    {
        return INonfungiblePositionManager.MintParams({
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
        });
    }
}
