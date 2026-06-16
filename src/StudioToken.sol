// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Capped} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title StudioToken (STD)
 * @author Studio
 * @notice 一个生产级 ERC-20 代币示例,基于 OpenZeppelin v5。
 *         设计目标:可作为简历作品 / 接单样板,展示标准代币 + 上限 + 链下授权(permit)。
 *
 * @dev 按 OpenZeppelin Contracts Wizard 的思路逐个组合扩展(继承链解释见下):
 *
 *  1. {ERC20}        —— 代币的核心实现:余额、转账、approve/allowance/transferFrom、
 *                       totalSupply、name/symbol/decimals。所有其他扩展都建立在它之上。
 *
 *  2. {ERC20Capped}  —— 给总供应量加一个不可变的硬顶 `cap`。它重写了 `_update` 钩子:
 *                       任何会增发(from == address(0),即 mint)的操作,如果导致
 *                       totalSupply 超过 cap,就会 revert(ERC20ExceededCap)。
 *                       注意:OZ v5 已移除 `_beforeTokenTransfer`/`_afterTokenTransfer`,
 *                       所有余额变动统一走 `_update` 钩子。
 *
 *  3. {ERC20Permit}  —— 实现 EIP-2612:允许持币人用一条链下签名来设置 allowance,
 *                       由别人代付 gas 调用 `permit(...)`。构造函数会用代币名字初始化
 *                       EIP-712 域分隔符(domain separator)。
 *
 *  4. {Ownable}      —— 最小化权限控制:存在一个 `owner`,`onlyOwner` 修饰的函数只有它能调。
 *                       OZ v5 的 Ownable 构造函数强制要求传入 `initialOwner`(不能是 0 地址),
 *                       这里我们传 msg.sender,即部署者成为初始 owner。
 *
 * 关于 OZ v5 的两个常见坑(本合约已规避):
 *  - 不要使用 increaseAllowance / decreaseAllowance:v5 已删除这两个函数。
 *    需要调整额度时,直接调用 approve(spender, newValue) 覆盖即可。
 *  - 不要使用 Counters 库:v5 已移除;nonce 由 ERC20Permit 内部的 Nonces 管理。
 */
contract StudioToken is ERC20, ERC20Capped, ERC20Permit, Ownable {
    /**
     * @param initialOwner 初始 owner(拥有 mint 权限)。
     * @param cap_         总供应量上限(单位:最小单位 wei,即已含 18 位小数)。必须 > 0。
     * @param initialSupply 部署时立即铸造给 initialOwner 的数量(单位:最小单位)。
     *                      传 0 表示部署时不预铸。initialSupply 必须 <= cap_,否则构造即 revert。
     *
     * @dev 多重继承时,各父合约的构造函数按"继承列表从左到右、深度优先"的顺序被调用;
     *      我们在初始化列表里显式给需要参数的父合约传参:
     *        - ERC20("Studio Token", "STD"):设定名称与符号
     *        - ERC20Capped(cap_):设定不可变上限
     *        - ERC20Permit("Studio Token"):用同名初始化 EIP-712 域(EIP-2612 建议与代币名一致)
     *        - Ownable(initialOwner):设定初始 owner
     */
    constructor(address initialOwner, uint256 cap_, uint256 initialSupply)
        ERC20("Studio Token", "STD")
        ERC20Capped(cap_)
        ERC20Permit("Studio Token")
        Ownable(initialOwner)
    {
        if (initialSupply > 0) {
            // 走 _mint -> _update,会自动经过 ERC20Capped 的上限检查
            _mint(initialOwner, initialSupply);
        }
    }

    /**
     * @notice 增发代币给 `to`。仅 owner 可调用。
     * @param to     接收地址,不能为 0 地址(由 ERC20 内部校验,违者 revert ERC20InvalidReceiver)。
     * @param amount 增发数量(最小单位)。若导致 totalSupply 超过 cap,会 revert ERC20ExceededCap。
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @dev 解决多重继承的菱形冲突:ERC20 与 ERC20Capped 都定义了 `_update`,
     *      Solidity 要求最派生合约显式重写并指明用 super 链。
     *      这里调用 super._update(...),C3 线性化会先走 ERC20Capped(执行上限检查),
     *      再走 ERC20(执行真正的余额变动),保证两者逻辑都生效。
     */
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Capped)
    {
        super._update(from, to, value);
    }
}
