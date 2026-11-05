// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IPositionManagerMint {
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

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

/// @title LockedLPMinter
/// @notice Uniswap v3 のポジション（NFT）を作り、同じ取引の中で PermanentLPLock に預ける。
///         NFT の番号は作られた瞬間にしか決まらない（直前に他人が作ると番号がずれる）ため、
///         「作る」と「ロックへ送る」を別々の送信にすると、送信前に予想した番号が外れることがある。
///         ここでは mint が返した実際の番号をそのままロックへ送るので、番号のずれが起きない。
///         - 呼んだ人のトークンを mint に必要な分だけ預かり、使われなかった分はその場で返す
///         - 状態を持たず、管理者もいない。誰が呼んでも、呼んだ人自身のトークンでポジションを作るだけ
contract LockedLPMinter {
    using SafeERC20 for IERC20;

    address public immutable positionManager;
    address public immutable lock;

    error ZeroAddress();

    constructor(address positionManager_, address lock_) {
        if (positionManager_ == address(0) || lock_ == address(0)) revert ZeroAddress();
        positionManager = positionManager_;
        lock = lock_;
    }

    /// @notice ポジションを作ってロックに預ける。手数料の受取人は beneficiary。
    ///         呼ぶ前に、amount0Desired / amount1Desired の分だけこのコントラクトへ approve しておく。
    ///         m.recipient は無視する（いったんこのコントラクトが受け取り、すぐロックへ送る）
    function mintLocked(IPositionManagerMint.MintParams memory m, address beneficiary)
        external
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        if (beneficiary == address(0)) revert ZeroAddress();
        _pull(m.token0, m.amount0Desired);
        _pull(m.token1, m.amount1Desired);

        m.recipient = address(this);
        (tokenId, liquidity, amount0, amount1) = IPositionManagerMint(positionManager).mint(m);
        IERC721(positionManager).safeTransferFrom(address(this), lock, tokenId, abi.encode(beneficiary));

        _refund(m.token0);
        _refund(m.token1);
    }

    function _pull(address token, uint256 amount) internal {
        if (amount == 0) return;
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(token).forceApprove(positionManager, amount);
    }

    function _refund(address token) internal {
        IERC20(token).forceApprove(positionManager, 0);
        uint256 left = IERC20(token).balanceOf(address(this));
        if (left > 0) IERC20(token).safeTransfer(msg.sender, left);
    }
}
