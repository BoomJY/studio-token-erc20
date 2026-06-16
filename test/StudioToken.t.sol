// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {StudioToken} from "../src/StudioToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Capped} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";

/**
 * @title StudioTokenTest
 * @notice StudioToken 的完整单元/模糊测试。
 *
 * 覆盖点(对应 Day4 作品验收清单):
 *  - 元数据(name/symbol/decimals/cap/owner/初始供应)
 *  - 转账成功 + Transfer 事件(expectEmit)
 *  - approve / allowance / transferFrom 全链路 + Approval 事件
 *  - 余额不足转账 revert(ERC20InsufficientBalance)
 *  - allowance 不足 transferFrom revert(ERC20InsufficientAllowance)
 *  - mint 仅 owner;非 owner 调用 revert(OwnableUnauthorizedAccount)
 *  - 超过 cap 的 mint revert(ERC20ExceededCap)
 *  - 恰好铸到 cap 成功;再多 1 wei 失败(边界)
 *  - permit(EIP-2612)链下签名授权成功 + 过期签名 revert
 *  - 对转账金额、mint 金额做 fuzz
 */
contract StudioTokenTest is Test {
    StudioToken internal token;

    // 测试账户
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant CAP = 1_000_000 ether; // 100 万枚上限
    uint256 internal constant INITIAL = 100_000 ether; // 部署预铸 10 万枚给 owner

    // 重新声明事件,供 expectEmit 匹配(签名需与 IERC20 一致)
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new StudioToken(owner, CAP, INITIAL);
    }

    /* ------------------------------------------------------------------ */
    /*                            元数据 / 初始化                           */
    /* ------------------------------------------------------------------ */

    function test_Metadata() public view {
        assertEq(token.name(), "Studio Token");
        assertEq(token.symbol(), "STD");
        assertEq(token.decimals(), 18);
        assertEq(token.cap(), CAP);
        assertEq(token.owner(), owner);
        assertEq(token.totalSupply(), INITIAL);
        assertEq(token.balanceOf(owner), INITIAL);
    }

    function test_Constructor_ZeroCapReverts() public {
        // cap 为 0 时 ERC20Capped 构造直接 revert
        vm.expectRevert(abi.encodeWithSelector(ERC20Capped.ERC20InvalidCap.selector, 0));
        new StudioToken(owner, 0, 0);
    }

    function test_Constructor_InitialSupplyOverCapReverts() public {
        // 预铸量超过 cap,构造时即触发上限检查
        vm.expectRevert(abi.encodeWithSelector(ERC20Capped.ERC20ExceededCap.selector, CAP + 1, CAP));
        new StudioToken(owner, CAP, CAP + 1);
    }

    function test_Constructor_NoPremint() public {
        StudioToken t = new StudioToken(owner, CAP, 0);
        assertEq(t.totalSupply(), 0);
        assertEq(t.balanceOf(owner), 0);
    }

    /* ------------------------------------------------------------------ */
    /*                               转账                                   */
    /* ------------------------------------------------------------------ */

    function test_Transfer() public {
        uint256 amount = 1_000 ether;

        // 期望触发 Transfer(owner -> alice, amount)
        vm.expectEmit(true, true, false, true);
        emit Transfer(owner, alice, amount);

        vm.prank(owner);
        bool ok = token.transfer(alice, amount);

        assertTrue(ok);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(owner), INITIAL - amount);
    }

    function test_Transfer_InsufficientBalanceReverts() public {
        // alice 余额为 0,转 1 wei 应失败
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1)
        );
        token.transfer(bob, 1);
    }

    function test_Transfer_ToZeroAddressReverts() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        token.transfer(address(0), 1 ether);
    }

    /* ------------------------------------------------------------------ */
    /*                    approve / allowance / transferFrom               */
    /* ------------------------------------------------------------------ */

    function test_ApproveAndAllowance() public {
        uint256 amount = 500 ether;

        vm.expectEmit(true, true, false, true);
        emit Approval(owner, alice, amount);

        vm.prank(owner);
        bool ok = token.approve(alice, amount);

        assertTrue(ok);
        assertEq(token.allowance(owner, alice), amount);
    }

    function test_TransferFrom() public {
        uint256 allowed = 800 ether;
        uint256 spend = 300 ether;

        // owner 授权 alice 花 800
        vm.prank(owner);
        token.approve(alice, allowed);

        // alice 代 owner 把 300 转给 bob
        vm.expectEmit(true, true, false, true);
        emit Transfer(owner, bob, spend);

        vm.prank(alice);
        bool ok = token.transferFrom(owner, bob, spend);

        assertTrue(ok);
        assertEq(token.balanceOf(bob), spend);
        assertEq(token.balanceOf(owner), INITIAL - spend);
        // allowance 应被扣减
        assertEq(token.allowance(owner, alice), allowed - spend);
    }

    function test_TransferFrom_InsufficientAllowanceReverts() public {
        uint256 allowed = 100 ether;

        vm.prank(owner);
        token.approve(alice, allowed);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, alice, allowed, allowed + 1
            )
        );
        token.transferFrom(owner, bob, allowed + 1);
    }

    function test_InfiniteAllowanceNotDecremented() public {
        // OZ v5:授权为 type(uint256).max 时视为无限额度,transferFrom 不扣减 allowance
        vm.prank(owner);
        token.approve(alice, type(uint256).max);

        vm.prank(alice);
        token.transferFrom(owner, bob, 1_000 ether);

        assertEq(token.allowance(owner, alice), type(uint256).max);
    }

    /* ------------------------------------------------------------------ */
    /*                              mint / cap                              */
    /* ------------------------------------------------------------------ */

    function test_Mint_ByOwner() public {
        uint256 amount = 5_000 ether;

        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), bob, amount); // mint 即 from == address(0)

        vm.prank(owner);
        token.mint(bob, amount);

        assertEq(token.balanceOf(bob), amount);
        assertEq(token.totalSupply(), INITIAL + amount);
    }

    function test_Mint_NonOwnerReverts() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice)
        );
        token.mint(alice, 1 ether);
    }

    function test_Mint_ExceedCapReverts() public {
        // 当前已铸 INITIAL,再铸 (CAP - INITIAL + 1) 会超过 cap
        uint256 over = CAP - INITIAL + 1;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(ERC20Capped.ERC20ExceededCap.selector, CAP + 1, CAP)
        );
        token.mint(bob, over);
    }

    function test_Mint_ExactlyToCapSucceeds() public {
        // 恰好铸满到 cap 应成功
        uint256 remaining = CAP - INITIAL;
        vm.prank(owner);
        token.mint(bob, remaining);
        assertEq(token.totalSupply(), CAP);

        // 再铸 1 wei 必须失败(边界)
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(ERC20Capped.ERC20ExceededCap.selector, CAP + 1, CAP)
        );
        token.mint(bob, 1);
    }

    /* ------------------------------------------------------------------ */
    /*                            ownership                                 */
    /* ------------------------------------------------------------------ */

    function test_TransferOwnership() public {
        vm.prank(owner);
        token.transferOwnership(alice);
        assertEq(token.owner(), alice);

        // 新 owner 能 mint,老 owner 不能
        vm.prank(alice);
        token.mint(bob, 1 ether);
        assertEq(token.balanceOf(bob), 1 ether);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner)
        );
        token.mint(bob, 1 ether);
    }

    /* ------------------------------------------------------------------ */
    /*                          permit (EIP-2612)                          */
    /* ------------------------------------------------------------------ */

    function test_Permit() public {
        // 用一个已知私钥派生签名者地址
        uint256 signerPk = 0xA11CE;
        address signer = vm.addr(signerPk);

        // 先给 signer 一些币,便于后续验证 transferFrom 真能花
        vm.prank(owner);
        token.transfer(signer, 1_000 ether);

        uint256 value = 600 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(signer);

        // 构造 EIP-712 摘要并签名
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                ),
                signer,
                bob,
                value,
                nonce,
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        // 任何人都可代为提交 permit(此处用 bob)
        vm.prank(bob);
        token.permit(signer, bob, value, deadline, v, r, s);

        assertEq(token.allowance(signer, bob), value);
        assertEq(token.nonces(signer), nonce + 1);

        // 验证授权确实可用
        vm.prank(bob);
        token.transferFrom(signer, bob, value);
        assertEq(token.balanceOf(bob), value);
    }

    function test_Permit_ExpiredReverts() public {
        uint256 signerPk = 0xB0B;
        address signer = vm.addr(signerPk);

        uint256 value = 1 ether;
        uint256 deadline = block.timestamp - 1; // 已过期
        uint256 nonce = token.nonces(signer);

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                ),
                signer,
                bob,
                value,
                nonce,
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        vm.expectRevert(
            abi.encodeWithSelector(bytes4(keccak256("ERC2612ExpiredSignature(uint256)")), deadline)
        );
        token.permit(signer, bob, value, deadline, v, r, s);
    }

    /* ------------------------------------------------------------------ */
    /*                                fuzz                                  */
    /* ------------------------------------------------------------------ */

    /// @dev 对转账金额做模糊测试:金额限定在 owner 余额范围内,转账后双方余额应守恒
    function testFuzz_Transfer(uint256 amount) public {
        amount = bound(amount, 0, INITIAL);

        uint256 ownerBefore = token.balanceOf(owner);
        uint256 aliceBefore = token.balanceOf(alice);

        vm.prank(owner);
        token.transfer(alice, amount);

        assertEq(token.balanceOf(owner), ownerBefore - amount);
        assertEq(token.balanceOf(alice), aliceBefore + amount);
    }

    /// @dev 对 mint 金额做模糊测试:不超过剩余额度则成功,超过则必 revert
    function testFuzz_MintRespectsCap(uint256 amount) public {
        uint256 remaining = CAP - token.totalSupply();
        amount = bound(amount, 0, remaining * 2 + 1); // 覆盖"未超 / 超过"两种情况

        if (amount <= remaining) {
            vm.prank(owner);
            token.mint(bob, amount);
            assertEq(token.balanceOf(bob), amount);
            assertLe(token.totalSupply(), CAP);
        } else {
            vm.prank(owner);
            vm.expectRevert(); // 超过 cap 必然 revert(具体 selector 在专门用例里已校验)
            token.mint(bob, amount);
        }
    }

    /// @dev 对 approve 金额做模糊测试:allowance 应等于设定值
    function testFuzz_Approve(uint256 amount) public {
        vm.prank(owner);
        token.approve(alice, amount);
        assertEq(token.allowance(owner, alice), amount);
    }
}
