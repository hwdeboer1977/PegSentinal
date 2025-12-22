// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {PegSentinelVault} from "../src/PegSentinelVault.sol";

// 1. source .env.anvil
// 2. forge script script/03_DeployVault.s.sol:DeployVault --rpc-url $RPC_URL --broadcast -vv --via-ir

contract DeployVault is Script {
    function run() external returns (PegSentinelVault vault) {
        bytes32 pk = vm.envBytes32("PRIVATE_KEY");

        address token0 = vm.envAddress("TOKEN0_ADDRESS");
        address token1 = vm.envAddress("TOKEN1_ADDRESS");
        address owner  = vm.envAddress("OWNER");

        vm.startBroadcast(uint256(pk));

        vault = new PegSentinelVault(token0, token1, owner);

        vm.stopBroadcast();

        console2.log("PegSentinelVault deployed at:", address(vault));
        console2.log("token0:", token0);
        console2.log("token1:", token1);
        console2.log("owner :", owner);
    }
}
