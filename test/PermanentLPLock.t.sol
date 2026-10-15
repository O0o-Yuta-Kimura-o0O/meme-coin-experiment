// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {PermanentLPLock, IPositionManagerCollect} from "../src/PermanentLPLock.sol";

/// @dev Uniswap の PositionManager の代わり。NFT を送る動きと、手数料の回収（collect）だけを真似る
contract MockPositionManager {
    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => uint256) public owedFees;
    address public lastRecipient;

    function mintTo(address to, uint256 id) external {
        ownerOf[id] = to;
    }

    function safeTransferFrom(address from, address to, uint256 id, bytes calldata data) external {
        require(ownerOf[id] == from && msg.sender == from, "not owner");
        ownerOf[id] = to;
        require(
            IERC721Receiver(to).onERC721Received(msg.sender, from, id, data)
                == IERC721Receiver.onERC721Received.selector,
            "rejected"
        );
    }

    function accrue(uint256 id, uint256 amount) external {
        owedFees[id] += amount;
    }

    function collect(IPositionManagerCollect.CollectParams calldata p) external returns (uint256, uint256) {
        require(ownerOf[p.tokenId] == msg.sender, "not owner");
        uint256 fees = owedFees[p.tokenId];
        owedFees[p.tokenId] = 0;
        lastRecipient = p.recipient;
        return (fees, 0);
    }
}

/// @notice ネットワーク不要の単体テスト（実際の Uniswap での確認は AddLiquidity.fork.t.sol）
contract PermanentLPLockTest is Test {
    MockPositionManager npm;
    PermanentLPLock lock;
    address kimura = makeAddr("kimura");
    address torima = makeAddr("torima");

    function setUp() public {
        npm = new MockPositionManager();
        lock = new PermanentLPLock(address(npm));
        npm.mintTo(address(this), 1);
        npm.mintTo(address(this), 2);
        npm.safeTransferFrom(address(this), address(lock), 1, abi.encode(kimura));
        npm.safeTransferFrom(address(this), address(lock), 2, abi.encode(torima));
    }

    function test_LocksWithBeneficiaries() public view {
        assertEq(npm.ownerOf(1), address(lock));
        assertEq(lock.beneficiaryOf(1), kimura);
        assertEq(lock.beneficiaryOf(2), torima);
    }

    function test_AnyoneCanCollectFeesToTheBeneficiary() public {
        npm.accrue(1, 123);
        vm.prank(makeAddr("anyone"));
        (uint256 a0,) = lock.collect(1);
        assertEq(a0, 123);
        assertEq(npm.lastRecipient(), kimura);
    }

    function test_EmptyDataMakesSenderTheBeneficiary() public {
        npm.mintTo(address(this), 3);
        npm.safeTransferFrom(address(this), address(lock), 3, "");
        assertEq(lock.beneficiaryOf(3), address(this));
    }

    function test_CollectRevertsForUnknownPosition() public {
        vm.expectRevert(PermanentLPLock.NotLocked.selector);
        lock.collect(999);
    }

    function test_OnlyBeneficiaryCanChangeBeneficiary() public {
        vm.prank(torima);
        vm.expectRevert(PermanentLPLock.NotBeneficiary.selector);
        lock.setBeneficiary(1, torima);

        vm.prank(kimura);
        vm.expectRevert(PermanentLPLock.ZeroAddress.selector);
        lock.setBeneficiary(1, address(0));

        address hw = makeAddr("hardware");
        vm.prank(kimura);
        lock.setBeneficiary(1, hw);
        assertEq(lock.beneficiaryOf(1), hw);
        npm.accrue(1, 5);
        lock.collect(1);
        assertEq(npm.lastRecipient(), hw);
    }

    function test_RejectsNftsFromOtherContracts() public {
        vm.expectRevert(PermanentLPLock.NotPositionManager.selector);
        lock.onERC721Received(address(this), address(this), 1, abi.encode(kimura));
    }
}
