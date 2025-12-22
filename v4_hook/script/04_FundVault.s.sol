// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PegSentinelVault} from "../src/PegSentinelVault.sol";

// 1. set -a 
// 2. source .env.anvil 
// 3. set +a
// 4. forge script script/04_FundVault.s.sol:FundVault --rpc-url $RPC_URL --broadcast -vv --via-ir


/// @notice Fund PegSentinelVault with token0/token1 from protocol treasury
/// Env vars expected:
/// - PRIVATE_KEY   (hex private key, 0x...)
/// - VAULT         (PegSentinelVault address)
/// - TOKEN0        (e.g. MockUSDC)
/// - TOKEN1        (e.g. MockUSDT)
/// - AMOUNT0       (amount of token0 to fund)
/// - AMOUNT1       (amount of token1 to fund)
contract FundVault is Script {
    function run() external {
        bytes32 pk = vm.envBytes32("PRIVATE_KEY");

        address vaultAddr = vm.envAddress("VAULT_ADDRESS");
        address token0 = vm.envAddress("TOKEN0_ADDRESS");
        address token1 = vm.envAddress("TOKEN1_ADDRESS");

        uint256 amount0 = vm.envUint("AMOUNT0");
        uint256 amount1 = vm.envUint("AMOUNT1");

        vm.startBroadcast(uint256(pk));

        PegSentinelVault vault = PegSentinelVault(payable(vaultAddr));

        // Optional safety logs
        console2.log("Funding vault:", vaultAddr);
        console2.log("token0 amount:", amount0);
        console2.log("token1 amount:", amount1);

        // NOTE:
        // OWNER must have approved the vault beforehand.
        IERC20(token0).approve(vaultAddr, type(uint256).max);
        IERC20(token1).approve(vaultAddr, type(uint256).max);
        vault.fund(amount0, amount1);

        vm.stopBroadcast();

        console2.log("Vault funded successfully");
    }
}
