// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MemeToken} from "../src/MemeToken.sol";
import {AddLiquidity, INonfungiblePositionManager} from "../script/AddLiquidity.s.sol";

interface IPositionManagerFull {
    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function decreaseLiquidity(DecreaseLiquidityParams calldata params) external payable returns (uint256, uint256);
    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);
}

interface ISwapRouter02 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface IERC721Owner {
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @notice Base Sepolia の実際の Uniswap v3 をフォークして、プール作成 → 購入 → 売却を確かめる。
///         BASE_SEPOLIA_RPC_URL が未設定ならスキップ（通常の forge test はネットワーク不要のまま）。
///         実行: BASE_SEPOLIA_RPC_URL=https://sepolia.base.org forge test --match-contract Fork --ffi -vv
///         （片側流動性のテストは、価格帯の計算に script/liquidity_params.py を使うため --ffi が必要）
contract AddLiquidityForkTest is Test {
    address constant WETH = 0x4200000000000000000000000000000000000006;
    ISwapRouter02 constant ROUTER = ISwapRouter02(0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4);
    uint256 constant LP_TOKENS = 900_000_000e18;
    uint256 constant LP_ETH = 0.02 ether;

    AddLiquidity script;
    MemeToken token;
    address buyer = makeAddr("buyer");

    function setUp() public {
        string memory rpc = vm.envOr("BASE_SEPOLIA_RPC_URL", string(""));
        if (bytes(rpc).length == 0) vm.skip(true);
        vm.createSelectFork(rpc);
        script = new AddLiquidity();
        token = new MemeToken("Test Coin", "TEST", LP_TOKENS, address(script));
        vm.deal(address(script), LP_ETH);
    }

    function test_CreatesPoolAndMintsFullRangePosition() public {
        AddLiquidity.Result memory r = script.addLiquidity(address(token), LP_TOKENS, LP_ETH, _me());
        assertTrue(r.pool != address(0));
        assertGt(r.liquidities[0], 0);
        assertGe(r.tokenUsed, LP_TOKENS * 99 / 100);
        assertGe(r.ethUsed, LP_ETH * 99 / 100);
        INonfungiblePositionManager npm = script.uniswapFor(block.chainid).positionManager;
        assertEq(IERC721Owner(address(npm)).ownerOf(r.tokenIds[0]), address(this));
    }

    function test_BuyAndSellThroughUniswap() public {
        script.addLiquidity(address(token), LP_TOKENS, LP_ETH, _me());

        // 購入：0.001 ETH → トークン（理論値 約 4,240万枚。手数料 1% とスリッページ込みで 4,000万枚以上）
        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);
        uint256 bought = ROUTER.exactInputSingle{value: 0.001 ether}(
            ISwapRouter02.ExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: address(token),
                fee: 10_000,
                recipient: buyer,
                amountIn: 0.001 ether,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
        assertGt(bought, 40_000_000e18);
        assertEq(token.balanceOf(buyer), bought);

        // 売却：買った全量 → WETH（往復で手数料 2% 分ほど目減りする）
        token.approve(address(ROUTER), bought);
        uint256 received = ROUTER.exactInputSingle(
            ISwapRouter02.ExactInputSingleParams({
                tokenIn: address(token),
                tokenOut: WETH,
                fee: 10_000,
                recipient: buyer,
                amountIn: bought,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
        vm.stopPrank();
        assertGt(received, 0.00097 ether);
        assertLt(received, 0.001 ether);
    }

    function test_RevertsIfPoolWasFrontRunAtAnotherPrice() public {
        // 攻撃者が先に、極端な価格でプールを作っておく
        INonfungiblePositionManager npm = script.uniswapFor(block.chainid).positionManager;
        (address t0, address t1) = address(token) < WETH ? (address(token), WETH) : (WETH, address(token));
        npm.createAndInitializePoolIfNecessary(t0, t1, 10_000, uint160(1 << 96));

        vm.expectRevert(bytes("pool already initialized at a different price"));
        script.addLiquidity(address(token), LP_TOKENS, LP_ETH, _me());
    }

    // ---------- 片側流動性（ETH を入れない） ----------

    uint256 constant SUPPLY = 1_000_000_000e18;

    function _me() internal view returns (address[] memory list) {
        list = new address[](1);
        list[0] = address(this);
    }

    function _singleSided(address at) internal returns (MemeToken t, AddLiquidity.Result memory r) {
        return _singleSided(at, _me());
    }

    function _singleSided(address at, address[] memory recipients)
        internal
        returns (MemeToken t, AddLiquidity.Result memory r)
    {
        deployCodeTo("MemeToken.sol:MemeToken", abi.encode("Test Coin", "TEST", SUPPLY, address(script)), at);
        t = MemeToken(at);
        // 開始時の FDV = 1 ETH（1 トークン ≈ 1e-9 ETH）
        string[] memory cmd = new string[](5);
        cmd[0] = "python3";
        cmd[1] = "script/liquidity_params.py";
        cmd[2] = vm.toString(at);
        cmd[3] = vm.toString(SUPPLY);
        cmd[4] = "1";
        string[] memory full = new string[](6);
        for (uint256 i; i < 5; i++) full[i] = cmd[i];
        full[5] = "--abi";
        (int24 lo, int24 hi, uint160 sqrtP) = abi.decode(vm.ffi(full), (int24, int24, uint160));
        r = script.addSingleSided(
            AddLiquidity.SingleSided({
                token: at,
                tokenAmount: LP_TOKENS,
                tickLower: lo,
                tickUpper: hi,
                initSqrtPriceX96: sqrtP,
                recipients: recipients
            })
        );
    }

    function _buy(MemeToken t, uint256 ethIn) internal returns (uint256) {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        return ROUTER.exactInputSingle{value: ethIn}(
            ISwapRouter02.ExactInputSingleParams(WETH, address(t), 10_000, buyer, ethIn, 0, 0)
        );
    }

    function _sell(MemeToken t, address seller, uint256 amount) internal returns (uint256) {
        vm.startPrank(seller);
        t.approve(address(ROUTER), amount);
        uint256 out = ROUTER.exactInputSingle(
            ISwapRouter02.ExactInputSingleParams(address(t), WETH, 10_000, seller, amount, 0, 0)
        );
        vm.stopPrank();
        return out;
    }

    function _checkSingleSided(address at) internal {
        (MemeToken t, AddLiquidity.Result memory r) = _singleSided(at);
        assertEq(r.ethUsed, 0, "no ETH should be needed");
        assertGe(r.tokenUsed, LP_TOKENS * 99 / 100);

        // 開始価格 ≈ 1e-9 ETH/枚 → 0.001 ETH で約 98 万枚（手数料 1% と開始価格の丸め +0.43% 込み）
        uint256 bought = _buy(t, 0.001 ether);
        assertGt(bought, 950_000e18);
        assertLt(bought, 1_000_000e18);

        // 売り戻すと、払った ETH から手数料分だけ減って戻る
        uint256 back = _sell(t, buyer, bought);
        assertGt(back, 0.00097 ether);
        assertLt(back, 0.001 ether);

        // 価格は開始価格より下がらない：プールの外のトークンを大量に売っても、プールにある ETH しか出てこない
        address holder = makeAddr("holder");
        deal(address(t), holder, 50_000_000e18);
        uint256 dumped = _sell(t, holder, 50_000_000e18);
        assertLt(dumped, 0.00003 ether);
    }

    function test_SingleSided_TokenIsToken0() public {
        _checkSingleSided(address(0x1111111111111111111111111111111111111111));
    }

    function test_SingleSided_TokenIsToken1() public {
        _checkSingleSided(address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));
    }

    // ---------- 受取人が二人（Team SEPPUKU の 50/50） ----------

    /// @dev ポジションの中身（元本 + 手数料）をすべて引き出し、受け取った WETH を返す
    function _withdrawAll(INonfungiblePositionManager npm, uint256 id, uint128 liq, address owner)
        internal
        returns (uint256 wethOut)
    {
        IPositionManagerFull pm = IPositionManagerFull(address(npm));
        vm.startPrank(owner);
        pm.decreaseLiquidity(IPositionManagerFull.DecreaseLiquidityParams(id, liq, 0, 0, block.timestamp));
        uint256 before = IERC20(WETH).balanceOf(owner);
        pm.collect(IPositionManagerFull.CollectParams(id, owner, type(uint128).max, type(uint128).max));
        vm.stopPrank();
        return IERC20(WETH).balanceOf(owner) - before;
    }

    function _checkTwoOwnersSplitEvenly(address at) internal {
        address kimura = makeAddr("kimura");
        address torima = makeAddr("torima");
        address[] memory owners = new address[](2);
        owners[0] = kimura;
        owners[1] = torima;
        (MemeToken t, AddLiquidity.Result memory r) = _singleSided(at, owners);

        INonfungiblePositionManager npm = script.uniswapFor(block.chainid).positionManager;
        assertEq(r.tokenIds.length, 2);
        assertEq(IERC721Owner(address(npm)).ownerOf(r.tokenIds[0]), kimura);
        assertEq(IERC721Owner(address(npm)).ownerOf(r.tokenIds[1]), torima);
        assertEq(r.liquidities[0], r.liquidities[1], "same amount and range -> same liquidity");
        assertEq(r.ethUsed, 0);

        // 何人かが買い、一部を売る（代金と手数料が二つのポジションにたまる）
        uint256 bought = _buy(t, 0.003 ether);
        _sell(t, buyer, bought / 3);

        uint256 k = _withdrawAll(npm, r.tokenIds[0], r.liquidities[0], kimura);
        uint256 m = _withdrawAll(npm, r.tokenIds[1], r.liquidities[1], torima);
        console2.log("WETH to owner 1 (wei):", k);
        console2.log("WETH to owner 2 (wei):", m);
        assertGt(k, 0);
        // 二人の受け取りは、端数（数 wei）を除いて同じ
        assertApproxEqAbs(k, m, 10);
    }

    function test_TwoOwners_TokenIsToken0() public {
        _checkTwoOwnersSplitEvenly(address(0x1111111111111111111111111111111111111111));
    }

    function test_TwoOwners_TokenIsToken1() public {
        _checkTwoOwnersSplitEvenly(address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE));
    }
}
