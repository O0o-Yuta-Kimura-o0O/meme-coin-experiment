# デプロイ記録

| 日時 (JST) | ネットワーク | Token | HalvingVesting（受取人ごと） | Pool / LP NFT | 備考 |
|---|---|---|---|---|---|
| 2026-10-15 13:47 | Base Sepolia（テストネット） | [0xa92b274f7ff72214702f2e39e40d497d91ca8b43](https://base-sepolia.blockscout.com/address/0xa92b274f7ff72214702f2e39e40d497d91ca8b43) | 木村: [0x2f2f52fe…1cbb](https://base-sepolia.blockscout.com/address/0x2f2f52fe5dd3de2ba5549101b99f33f31b561cbb) / 鳥間（代理 Account3）: [0xf34206fd…a272](https://base-sepolia.blockscout.com/address/0xf34206fd60d93151d1510300d13da2f66c08a272) | Pool [0x8995…B0c1](https://base-sepolia.blockscout.com/address/0x899555FE9d766c44D6B47ED0F967A47ACFD8B0c1) / LP NFT #82963（片側流動性、FDV 1 ETH、ETH 0。手数料 約 0.000031 ETH） | 3件とも Blockscout で検証済み。半減期の最初の解放 2026-10-15 14:41 JST（以後1時間ごと）。ガス代 約 0.0000135 ETH |
| 2026-10-15 17:0x | Base Sepolia（テストネット・2 回目） | [0xc0D073e0250202AB959c2875064Ca11C85Ae08eA](https://base-sepolia.blockscout.com/address/0xc0D073e0250202AB959c2875064Ca11C85Ae08eA) | 木村: [0x38Bd…6C1F](https://base-sepolia.blockscout.com/address/0x38Bd24BCcE7098541133a3E5C366A6fC66d13C1F) / 鳥間（代理 Account3）: [0x84E7…DEb8](https://base-sepolia.blockscout.com/address/0x84E74E23Fc10b1F9956F30BE7AEe186CcF52DEb8) | Pool [0x14e5…4C8A](https://base-sepolia.blockscout.com/address/0x14e5B931c83fCAf419ADd9cDb381F0Ac6E0e4C8A) / LP NFT #82983（Account1）・#82984（Account3）。同じ量・同じ価格帯 | **LP を二人分に分けた構成。サイトはこちらを表示**。3 件とも Blockscout で検証済み。ガス代 計 約 0.000046 ETH |

## テストネットでの動作確認（2026-10-15）

| 時刻 (JST) | 確認したこと | 結果 |
|---|---|---|
| 13:47 | デプロイ（トークン + 半減期ロック 2 つ） | 成功。配分 9億 / 2,500万 × 2 / 5,000万。3 件とも Blockscout で検証済み |
| 14:5x | 片側流動性の追加 | 成功。トークン 9億枚、ETH 0 |
| 15:0x | 購入 0.0001 ETH | 98,564 枚（理論値どおり） |
| 15:0x | 半減期 1 回目の解放（二人分） | Account1・Account3 に 1,250 万枚ずつ |
| 15:1x | 売却 98,564 枚 | 0.000098 WETH を受領（往復の手数料 約 2%）。プールのトークンは 9億枚に戻った |
| 15:4x | 半減期 2 回目の解放（二人分） | Account1・Account3 とも累計 1,875 万枚（75%）。残り 625 万枚ずつロック中 |
