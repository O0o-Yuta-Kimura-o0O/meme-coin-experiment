// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title HalvingVesting
/// @notice ビットコインの半減期を模したチーム分ロック。
///         クリフ終了時に 50%、以後 period ごとに残りの半分ずつ解放され、
///         halvings 回目で全量解放される。
///           1回目: 50% / 2回目: 75% / 3回目: 87.5% / ... / halvings回目: 100%
///         管理者なし・設定変更不可。release() は誰でも呼べ、常に beneficiary に送られる。
contract HalvingVesting {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    address public immutable beneficiary;
    uint64 public immutable start; // 最初の解放時刻（= デプロイ時刻 + クリフ）
    uint64 public immutable period; // 半減期の間隔（秒）
    uint8 public immutable halvings; // この回数で全量解放

    uint256 public released;

    event Released(uint256 amount);

    error ZeroAddress();
    error InvalidSchedule();

    constructor(IERC20 token_, address beneficiary_, uint64 start_, uint64 period_, uint8 halvings_) {
        if (address(token_) == address(0) || beneficiary_ == address(0)) revert ZeroAddress();
        if (period_ == 0 || halvings_ == 0 || halvings_ > 64) revert InvalidSchedule();
        token = token_;
        beneficiary = beneficiary_;
        start = start_;
        period = period_;
        halvings = halvings_;
    }

    /// @notice 時刻 t までに解放済み（引き出し可能 + 引き出し済み）の総量
    function vestedAmount(uint64 t) public view returns (uint256) {
        uint256 total = token.balanceOf(address(this)) + released;
        if (t < start) return 0;
        uint256 n = uint256(t - start) / period + 1; // 経過した半減期の回数
        if (n >= halvings) return total;
        return total - (total >> n); // total * (1 - 1/2^n)
    }

    /// @notice 今引き出せる量
    function releasable() public view returns (uint256) {
        return vestedAmount(uint64(block.timestamp)) - released;
    }

    /// @notice 解放済み分を beneficiary に送る（誰が呼んでも良い）
    function release() external {
        uint256 amount = releasable();
        released += amount;
        emit Released(amount);
        token.safeTransfer(beneficiary, amount);
    }
}
