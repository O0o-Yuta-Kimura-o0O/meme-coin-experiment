// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/// @title MemeToken
/// @notice 維持費ゼロ設計のミームコイン。
///         - 発行はデプロイ時の1回のみ（追加発行 mint 関数なし）
///         - オーナー / 管理者権限なし（最初から "renounced" 状態）
///         - 売買税・ブラックリスト・一時停止なし（ハニーポット判定されない）
///         - burn（自分の保有分の焼却）と permit（ガスレス承認）のみ追加
contract MemeToken is ERC20, ERC20Burnable, ERC20Permit {
    constructor(string memory name_, string memory symbol_, uint256 totalSupply_, address recipient)
        ERC20(name_, symbol_)
        ERC20Permit(name_)
    {
        _mint(recipient, totalSupply_);
    }
}
