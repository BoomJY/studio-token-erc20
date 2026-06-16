# 02 · Foundry ERC-20 代币(Studio Token / STD)

> Web3 作品集 · 作品 #1
> 对应计划:**solidity-15天补枪路线 · Day4(ERC-20 代币)**
> 技术栈:Solidity 0.8.28 + Foundry + OpenZeppelin Contracts v5.1.0

一个**生产级 ERC-20 代币**示例。在 OpenZeppelin v5 标准实现之上组合了「供应量上限」与「链下签名授权(EIP-2612 permit)」两个扩展,并配有 **21 个单元/模糊测试(全绿)** 和一份可直接用于测试网/主网的部署脚本。既是简历级代码,也是接单时可复用的样板。

---

## 1. 这是什么

`StudioToken` 是一个标准的、可增发但有硬顶的 ERC-20 代币:

- **标准 ERC-20**:余额、转账、`approve`/`allowance`/`transferFrom`、`name`/`symbol`/`decimals`、`totalSupply`。
- **可增发(mint)**:只有 `owner` 能增发(`onlyOwner`)。
- **供应量上限(cap)**:总供应量有一个**不可变的硬顶**,任何会使 `totalSupply` 超过 `cap` 的增发都会 revert。
- **链下授权(permit / EIP-2612)**:持币人可以用一条**链下签名**来设置 allowance,由第三方代付 gas 调用 `permit(...)`——常用于「无 gas 授权」「一笔交易内 approve+操作」等场景。
- **所有权(Ownable)**:可转移 owner;`owner` 拥有 mint 权限。

| 参数 | 值 |
|---|---|
| 名称 / 符号 | Studio Token / `STD` |
| 小数位 | 18 |
| 上限 cap | 构造时传入(部署脚本默认 1 亿枚) |
| 预铸 initialSupply | 构造时传入(部署脚本默认 1000 万枚,铸给 owner) |

---

## 2. 设计要点(按 OpenZeppelin Wizard 思路逐个解释继承)

合约的继承声明:

```solidity
contract StudioToken is ERC20, ERC20Capped, ERC20Permit, Ownable
```

逐个拆解(这也是用 [OpenZeppelin Contracts Wizard](https://wizard.openzeppelin.com/) 勾选扩展时,背后真正发生的事):

| 继承 | 作用 | 关键点 |
|---|---|---|
| **`ERC20`** | 代币核心实现 | 提供余额/转账/授权/元数据。所有其他扩展都建立在它之上。 |
| **`ERC20Capped`** | 总供应量硬顶 | 构造传入 `cap_`(必须 > 0,否则 `ERC20InvalidCap`)。它重写 `_update` 钩子,在 mint(`from == address(0)`)后检查是否超顶,超了就 `ERC20ExceededCap`。 |
| **`ERC20Permit`** | EIP-2612 链下授权 | 提供 `permit(...)`、`nonces(...)`、`DOMAIN_SEPARATOR()`。构造用代币名初始化 EIP-712 域分隔符(EIP-2612 建议域名与代币名一致)。 |
| **`Ownable`** | 最小权限控制 | 提供 `owner()`、`onlyOwner`、`transferOwnership`。**OZ v5 必须在构造传 `initialOwner`**,本合约传 `msg.sender`。 |

### `_update` 钩子的菱形冲突处理

`ERC20` 和 `ERC20Capped` 都定义了 `_update`,多重继承产生菱形,Solidity 要求最派生合约**显式重写并指明 override 列表**:

```solidity
function _update(address from, address to, uint256 value)
    internal
    override(ERC20, ERC20Capped)
{
    super._update(from, to, value);
}
```

`super._update(...)` 借助 C3 线性化:先走 `ERC20Capped`(执行上限检查),再走 `ERC20`(执行真正的余额变动),两者逻辑都生效。

### 刻意规避的 OZ v5 雷区

> OZ v5 相对 v4 有 break change,以下是本项目特意避开的坑:

- **不用 `increaseAllowance` / `decreaseAllowance`**:v5 已删除。需要改额度时直接 `approve(spender, newValue)` 覆盖。
- **不用 `Counters` 库**:v5 已移除;permit 的 nonce 由内置的 `Nonces` 管理(通过 `nonces(owner)` 读取)。
- **不用 `_beforeTokenTransfer` / `_afterTokenTransfer`**:v5 已移除,所有余额变动统一走 `_update` 钩子。
- **`Ownable` 构造必须传 `initialOwner`**:v4 是隐式 `msg.sender`,v5 改成显式参数且禁止 0 地址。

---

## 3. 目录结构

```
02-foundry-erc20-token/
├── src/
│   └── StudioToken.sol            # 代币合约(本项目核心)
├── script/
│   └── DeployStudioToken.s.sol    # 部署脚本(参数走环境变量,带默认值)
├── test/
│   └── StudioToken.t.sol          # 21 个单元 + 模糊测试
├── lib/
│   ├── forge-std/                 # Foundry 标准库
│   └── openzeppelin-contracts/    # OZ v5.1.0
├── foundry.toml                   # 编译器 0.8.28 + 优化器 + fuzz 配置
├── remappings.txt                 # import 路径映射
└── README.md
```

---

## 4. 如何 build / test / 运行

> **Windows 环境说明**:本机 `forge`/`cast` 不在 PATH,请用绝对路径调用,例如
> `C:/Users/<你的用户名>/foundry/forge.exe`。
> 下文为简洁统一写作 `forge`,实际请替换为绝对路径。
> **务必在 ASCII 路径下构建**(本项目位于 `E:\` 盘);含中文(CJK)的路径会导致 `forge build` 报 `Error writing output JSON`。

### 编译

```bash
forge build
```

### 跑测试(应全绿)

```bash
forge test            # 简洁输出
forge test -vv        # 带日志
forge test -vvvv      # 出错时看完整 trace
```

### 看 gas 报告 / 覆盖率(可选)

```bash
forge test --gas-report
forge coverage
```

### 本地试跑部署脚本(不广播、不需要私钥)

```bash
forge script script/DeployStudioToken.s.sol
```

会打印部署后的地址、名称、符号、owner、cap、totalSupply。

---

## 5. 测试覆盖一览(21 项,全部通过)

| 分类 | 用例 |
|---|---|
| 元数据/初始化 | name/symbol/decimals/cap/owner/初始供应;cap=0 revert;预铸超 cap revert;不预铸 |
| 转账 | 成功转账 + `Transfer` 事件(`expectEmit`);**余额不足 revert**;转给 0 地址 revert |
| 授权链路 | `approve` + `Approval` 事件;`transferFrom` 全链路 + allowance 扣减;**allowance 不足 revert**;无限额度(`type(uint256).max`)不扣减 |
| mint / cap | owner 增发 + mint 事件;**非 owner 增发 revert**;**超 cap revert**;恰好铸满到 cap 成功、再多 1 wei 失败(边界) |
| 所有权 | 转移 owner 后新 owner 能 mint、老 owner 不能 |
| permit (EIP-2612) | 链下签名授权成功 + nonce 自增 + 授权可用;过期签名 revert |
| **模糊测试(fuzz)** | 转账金额 fuzz(余额守恒);mint 金额 fuzz(尊重 cap);approve 金额 fuzz |

最近一次本地运行结果:

```
Ran 21 tests for test/StudioToken.t.sol:StudioTokenTest
[PASS] testFuzz_Approve(uint256) (runs: 256, ...)
[PASS] testFuzz_MintRespectsCap(uint256) (runs: 256, ...)
[PASS] testFuzz_Transfer(uint256) (runs: 256, ...)
[PASS] test_Metadata() ...
... (略)
Suite result: ok. 21 passed; 0 failed; 0 skipped
```

---

## 6. 部署到测试网 / 主网 —— 🚫 需要你本人填写的「物理条件」

代码与命令都已就绪,**真实上链需要你提供以下两样东西**(私钥不能托管给 AI):

| 你需要准备 | 说明 |
|---|---|
| **RPC URL** | 一个节点服务地址,如 Alchemy / Infura 的 Sepolia 端点。去对应平台注册即可拿到。 |
| **部署账户私钥** | 一个有测试网 ETH 的账户私钥(测试网 ETH 去 faucet 领)。**绝不要把主网大额账户私钥贴进命令行/文件。** |

可选环境变量(都有默认值,见脚本注释):

| 变量 | 含义 | 默认 |
|---|---|---|
| `CAP` | 上限(单位:**枚**,脚本内部 ×1e18) | 100000000 |
| `INITIAL_SUPPLY` | 预铸量(单位:**枚**) | 10000000 |
| `INITIAL_OWNER` | 初始 owner 地址 | 广播账户自身 |

### 部署命令(以 Sepolia 测试网为例)

```powershell
# 1) 设置环境变量(PowerShell 写法)
$env:SEPOLIA_RPC_URL = "https://eth-sepolia.g.alchemy.com/v2/<你的KEY>"
$env:PRIVATE_KEY     = "0x<你的测试账户私钥>"

# 2) 广播部署
forge script script/DeployStudioToken.s.sol `
  --rpc-url $env:SEPOLIA_RPC_URL `
  --private-key $env:PRIVATE_KEY `
  --broadcast
```

### (可选)在 Etherscan 上验证源码

需要额外准备 **Etherscan API Key**,在上面命令追加:

```powershell
  --verify --etherscan-api-key $env:ETHERSCAN_API_KEY
```

---

## 7. 安全 / 边界说明

- **owner 拥有无限增发权(在 cap 之内)**:这是设计选择(常见于项目方代币)。若要去信任化,可在部署后 `renounceOwnership()` 永久放弃增发,或改用多签 / 时间锁作为 owner。
- **cap 不可变**:部署后无法调整,请在部署前确认 `CAP` 数值。
- **permit 的重放保护**:依赖 EIP-712 域分隔符(绑定 chainId 与合约地址)+ 每地址递增的 nonce,签名一次性有效、不可跨链复用。
- 本合约未加 `Pausable` / 黑名单 / 增发时间锁等额外管控——保持最小、可审计。如接单需求需要,可按 OZ Wizard 思路再叠加。

---

## 8. 许可证

MIT
