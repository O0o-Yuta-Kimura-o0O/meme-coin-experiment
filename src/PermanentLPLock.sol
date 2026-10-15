// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

interface IPositionManagerCollect {
    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);
}

/// @title PermanentLPLock
/// @notice Uniswap v3 の流動性ポジション（NFT）を永久に預かる。
///         - 引き出す機能（NFT の返却、流動性の減少）は存在しない。誰も（発行者自身も）元本を取り出せない
///         - 取引手数料だけは、誰が collect() を呼んでも、そのポジションの受取人に届く
///         - 受取人は、受取人本人だけが変更できる（ウォレットの移行や相続のため）。受取人が鍵を失っても、
///           プールでの売買には影響しない
///         - 管理者はいない
contract PermanentLPLock is IERC721Receiver {
    address public immutable positionManager;

    /// @notice ポジション（NFT の番号）→ 手数料の受取人
    mapping(uint256 => address) public beneficiaryOf;

    event Locked(uint256 indexed tokenId, address indexed beneficiary);
    event FeesCollected(uint256 indexed tokenId, address indexed beneficiary, uint256 amount0, uint256 amount1);
    event BeneficiaryChanged(uint256 indexed tokenId, address indexed from, address indexed to);

    error NotPositionManager();
    error ZeroAddress();
    error NotLocked();
    error NotBeneficiary();

    constructor(address positionManager_) {
        if (positionManager_ == address(0)) revert ZeroAddress();
        positionManager = positionManager_;
    }

    /// @notice NFT を safeTransferFrom で送ると、ここで永久ロックされる。
    ///         data に受取人のアドレス（abi.encode(address)）を入れる。空なら送った人が受取人になる
    function onERC721Received(address, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4)
    {
        if (msg.sender != positionManager) revert NotPositionManager();
        address beneficiary = data.length == 32 ? abi.decode(data, (address)) : from;
        if (beneficiary == address(0)) revert ZeroAddress();
        beneficiaryOf[tokenId] = beneficiary;
        emit Locked(tokenId, beneficiary);
        return IERC721Receiver.onERC721Received.selector;
    }

    /// @notice たまった取引手数料を受取人に送る（誰が呼んでもよい）。
    ///         このコントラクトは流動性を減らさないので、回収されるのは手数料だけで、元本はプールに残る
    function collect(uint256 tokenId) external returns (uint256 amount0, uint256 amount1) {
        address beneficiary = beneficiaryOf[tokenId];
        if (beneficiary == address(0)) revert NotLocked();
        (amount0, amount1) = IPositionManagerCollect(positionManager).collect(
            IPositionManagerCollect.CollectParams(tokenId, beneficiary, type(uint128).max, type(uint128).max)
        );
        emit FeesCollected(tokenId, beneficiary, amount0, amount1);
    }

    /// @notice 手数料の受取人を変える（今の受取人だけができる）
    function setBeneficiary(uint256 tokenId, address to) external {
        address from = beneficiaryOf[tokenId];
        if (from == address(0)) revert NotLocked();
        if (msg.sender != from) revert NotBeneficiary();
        if (to == address(0)) revert ZeroAddress();
        beneficiaryOf[tokenId] = to;
        emit BeneficiaryChanged(tokenId, from, to);
    }
}
