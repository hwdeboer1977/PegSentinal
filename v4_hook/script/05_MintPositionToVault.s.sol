// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";

import {BaseScript} from "./base/BaseScript.sol";
import {LiquidityHelpers} from "./base/LiquidityHelpers.sol";

import {PegSentinelVault} from "../src/PegSentinelVault.sol";

// 1. set -a; source .env.anvil; set +a;
// 2. forge script script/05_MintPositionToVault.s.sol:MintPositionToVault --rpc-url $RPC_URL --broadcast -vvvv --via-ir


/// Minimal interface for Permit2 approve used in your helper
interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

contract MintPositionToVault is Script, BaseScript, LiquidityHelpers {
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    uint24 lpFee = LPFeeLibrary.DYNAMIC_FEE_FLAG;
    int24 tickSpacing = 60;

    function run() external {
        // ---- env ----
        bytes32 pk = vm.envBytes32("PRIVATE_KEY");
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");
        uint256 amount0 = vm.envUint("AMOUNT0");
        uint256 amount1 = vm.envUint("AMOUNT1");

        PegSentinelVault vault = PegSentinelVault(payable(vaultAddr));

        // ---- pool key ----
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: hookContract
        });

        bytes memory hookData = new bytes(0);

        // ---- compute ticks & liquidity ----
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolKey.toId());
        int24 currentTick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);

        int24 tickLower = truncateTickSpacing((currentTick - 1000 * tickSpacing), tickSpacing);
        int24 tickUpper = truncateTickSpacing((currentTick + 1000 * tickSpacing), tickSpacing);

        uint128 liq = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0,
            amount1
        );

        uint256 amount0Max = amount0 + 1;
        uint256 amount1Max = amount1 + 1;

        // ---- build MINT_POSITION action bundle ----
        (bytes memory actions, bytes[] memory params) =
            _mintLiquidityParams(
                poolKey,
                tickLower,
                tickUpper,
                uint256(liq),
                amount0Max,
                amount1Max,
                vaultAddr, // << recipient/owner of the position NFT
                hookData
            );

        // Payload for positionManager.modifyLiquidities(abi.encode(actions, params), deadline)
        bytes memory mintCall = abi.encodeWithSelector(
            positionManager.modifyLiquidities.selector,
            abi.encode(actions, params),
            block.timestamp + 60
        );

        // Only needed if currency0 is native ETH
        uint256 valueToPass = currency0.isAddressZero() ? amount0Max : 0;

        vm.startBroadcast(uint256(pk));

        // ---- allowlist targets the vault will call ----
        vault.setAllowedTarget(address(positionManager), true);
        vault.setAllowedTarget(address(permit2), true);

        // Unwrap Currency -> token address (your v4-core uses Currency.unwrap(...) style)
        address t0 = address(0);
        address t1 = address(0);

        if (!currency0.isAddressZero()) {
            t0 = Currency.unwrap(currency0);
            vault.setAllowedTarget(t0, true);
        }
        if (!currency1.isAddressZero()) {
            t1 = Currency.unwrap(currency1);
            vault.setAllowedTarget(t1, true);
        }

        // ---- approvals must be done BY THE VAULT ----
        // Mirror LiquidityHelpers.tokenApprovals(), but executed via vault.execute()

        if (!currency0.isAddressZero()) {
            // token0.approve(permit2, max)
            vault.execute(
                t0,
                0,
                abi.encodeWithSelector(IERC20.approve.selector, address(permit2), type(uint256).max)
            );
            // permit2.approve(token0, positionManager, max160, max48)
            vault.execute(
                address(permit2),
                0,
                abi.encodeWithSelector(
                    IPermit2.approve.selector,
                    t0,
                    address(positionManager),
                    type(uint160).max,
                    type(uint48).max
                )
            );
        }

        if (!currency1.isAddressZero()) {
            vault.execute(
                t1,
                0,
                abi.encodeWithSelector(IERC20.approve.selector, address(permit2), type(uint256).max)
            );
            vault.execute(
                address(permit2),
                0,
                abi.encodeWithSelector(
                    IPermit2.approve.selector,
                    t1,
                    address(positionManager),
                    type(uint160).max,
                    type(uint48).max
                )
            );
        }

        // Get tokenId before minting
        uint256 tokenId = positionManager.nextTokenId();
        console2.log("Next Token ID (will be yours):", tokenId);

        // ---- mint FROM THE VAULT ----
        bytes memory ret = vault.execute(address(positionManager), valueToPass, mintCall);

        vm.stopBroadcast();

        console2.log("Minted new position to vault:", vaultAddr);
        console2.log("tickLower:", tickLower);
        console2.log("tickUpper:", tickUpper);
        console2.log("amount0:", amount0);
        console2.log("amount1:", amount1);
        console2.logBytes(ret);

        
    }
}