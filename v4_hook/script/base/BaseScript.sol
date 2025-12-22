// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {Deployers} from "test/utils/Deployers.sol";

/// @notice Shared configuration between scripts (env-driven)
/// Env vars expected:
/// - TOKEN0 (address)
/// - TOKEN1 (address)
/// Optional:
/// - HOOK_CONTRACT (address)  // set to 0x0 if none
contract BaseScript is Script, Deployers {
    address immutable deployerAddress;

    // Now configurable via env (not constants)
    IERC20 internal token0;
    IERC20 internal token1;
    IHooks internal hookContract;

    Currency internal currency0;
    Currency internal currency1;

    constructor() {
        // Deploy or configure periphery artifacts (Permit2/PoolManager/PositionManager/Router)
        deployArtifacts();

        deployerAddress = getDeployer();

        // Load addresses from env
        token0 = IERC20(vm.envAddress("TOKEN0_ADDRESS"));
        token1 = IERC20(vm.envAddress("TOKEN1_ADDRESS"));

        // Hook is optional; if env var missing or set to 0, use address(0)
        // If you prefer "required", replace with vm.envAddress("HOOK_CONTRACT")
        address hookAddr = vm.envOr("HOOK_ADDRESS", address(0));
        hookContract = IHooks(hookAddr);

        (currency0, currency1) = getCurrencies();

        // Labels for readability in traces
        vm.label(address(permit2), "Permit2");
        vm.label(address(poolManager), "V4PoolManager");
        vm.label(address(positionManager), "V4PositionManager");
        vm.label(address(swapRouter), "V4SwapRouter");

        vm.label(address(token0), "Token0");
        vm.label(address(token1), "Token1");
        vm.label(address(hookContract), "HookContract");
    }

    function _etch(address target, bytes memory bytecode) internal override {
        if (block.chainid == 31337) {
            vm.rpc(
                "anvil_setCode",
                string.concat(
                    '["',
                    vm.toString(target),
                    '",',
                    '"',
                    vm.toString(bytecode),
                    '"]'
                )
            );
        } else {
            revert("Unsupported etch on this network");
        }
    }

    function getCurrencies() internal view returns (Currency, Currency) {
        require(address(token0) != address(token1), "token0 == token1");

        // Sort by address to satisfy PoolKey ordering rules
        if (address(token0) < address(token1)) {
            return (Currency.wrap(address(token0)), Currency.wrap(address(token1)));
        } else {
            return (Currency.wrap(address(token1)), Currency.wrap(address(token0)));
        }
    }

    function getDeployer() internal returns (address) {
        address[] memory wallets = vm.getWallets();
        if (wallets.length > 0) return wallets[0];
        return msg.sender;
    }
}
