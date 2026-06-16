// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {StudioToken} from "../src/StudioToken.sol";

/**
 * @title DeployStudioToken
 * @notice StudioToken 的部署脚本。
 *
 * @dev 部署参数通过环境变量读取,均带默认值,方便本地 dry-run:
 *      - CAP            : 总供应量上限(单位:代币个数,脚本内部会乘以 1e18)。默认 100_000_000。
 *      - INITIAL_SUPPLY : 部署时预铸数量(单位:代币个数,内部乘以 1e18)。默认 10_000_000。
 *      - INITIAL_OWNER  : 初始 owner 地址。默认使用广播者(broadcaster)地址。
 *
 *      本地试跑(不广播、不需要私钥):
 *        forge.exe script script/DeployStudioToken.s.sol
 *
 *      真实部署(需要 RPC + 私钥,见 README 的"物理条件"一节):
 *        forge.exe script script/DeployStudioToken.s.sol \
 *          --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast
 */
contract DeployStudioToken is Script {
    function run() external returns (StudioToken token) {
        // 读取上限与预铸量(以"个"为单位),再换算成最小单位(18 位小数)
        uint256 capTokens = vm.envOr("CAP", uint256(100_000_000));
        uint256 initialSupplyTokens = vm.envOr("INITIAL_SUPPLY", uint256(10_000_000));

        uint256 cap = capTokens * 1e18;
        uint256 initialSupply = initialSupplyTokens * 1e18;

        // 广播者:使用 --private-key / --account 指定的账户;dry-run 时为默认测试地址
        address broadcaster = msg.sender;
        address initialOwner = vm.envOr("INITIAL_OWNER", broadcaster);

        vm.startBroadcast();
        token = new StudioToken(initialOwner, cap, initialSupply);
        vm.stopBroadcast();

        console.log("StudioToken deployed at:", address(token));
        console.log("  name        :", token.name());
        console.log("  symbol      :", token.symbol());
        console.log("  owner       :", token.owner());
        console.log("  cap (wei)   :", token.cap());
        console.log("  totalSupply :", token.totalSupply());
    }
}
