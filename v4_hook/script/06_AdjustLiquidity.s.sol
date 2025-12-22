// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

// 1. set -a; source .env.anvil; set +a
// 2. forge script script/06_AdjustLiquidity.s.sol:AdjustLiquidityScript --rpc-url $RPC_URL --broadcast -vv --via-ir


import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";

import {BaseScript} from "./base/BaseScript.sol";
import {LiquidityHelpers} from "./base/LiquidityHelpers.sol";

import {PegSentinelVault} from "../src/PegSentinelVault.sol";

interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

/// @notice Rebalance a vault-owned Uniswap v4 position:
/// 1) Reads current liquidity from PoolManager.getPositionInfo (needs old ticks + salt scheme)
/// 2) Decreases (withdraws) liquidity to the vault
/// 3) Mints a NEW position to the vault with a new range centered around current price
///
/// Required env vars:
/// - PRIVATE_KEY
/// - VAULT_ADDRESS
/// - TOKEN_ID_OLD
/// - OLD_TICK_LOWER
/// - OLD_TICK_UPPER
/// - AMOUNT0_MIN (suggest 0 for POC)
/// - AMOUNT1_MIN (suggest 0 for POC)
///
/// Optional env vars:
/// - LP_FEE (default DYNAMIC_FEE_FLAG)
/// - TICK_SPACING (default 60)
/// - RANGE_MULT_NEW (default 1000)
/// - DEADLINE_SECONDS (default 300)
contract AdjustLiquidityScript is Script, BaseScript, LiquidityHelpers {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    function run() external {
        // ---------- env ----------
        uint256 pk = uint256(vm.envBytes32("PRIVATE_KEY"));
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");

        uint256 tokenIdOld = vm.envUint("TOKEN_ID_OLD");
        int24 oldTickLower = int24(int256(vm.envInt("OLD_TICK_LOWER")));
        int24 oldTickUpper = int24(int256(vm.envInt("OLD_TICK_UPPER")));

        uint256 amount0Min = vm.envOr("AMOUNT0_MIN", uint256(0));
        uint256 amount1Min = vm.envOr("AMOUNT1_MIN", uint256(0));

        uint24 lpFee = uint24(vm.envOr("LP_FEE", uint256(LPFeeLibrary.DYNAMIC_FEE_FLAG)));
        int24 tickSpacing = int24(int256(vm.envOr("TICK_SPACING", uint256(60))));
        int24 rangeMultNew = int24(int256(vm.envOr("RANGE_MULT_NEW", uint256(1000))));
        uint256 deadlineSeconds = vm.envOr("DEADLINE_SECONDS", uint256(300));

        PegSentinelVault vault = PegSentinelVault(payable(vaultAddr));

        // ---------- pool key ----------
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: hookContract
        });

        PoolId pid = poolKey.toId();
        bytes memory hookData = new bytes(0);

        // ---------- read pool state ----------
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(pid);
        int24 currentTick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);

        // ---------- read OLD position liquidity from PoolManager ----------
        // IMPORTANT: salt scheme must match your CheckLiquidityScript
        bytes32 salt = bytes32(tokenIdOld);

        (uint128 liqOld,,) =
            poolManager.getPositionInfo(pid, address(positionManager), oldTickLower, oldTickUpper, salt);

        console2.log("=== AdjustLiquidity ===");
        console2.log("tokenIdOld:", tokenIdOld);
        console2.log("oldTickLower:", int256(oldTickLower));
        console2.log("oldTickUpper:", int256(oldTickUpper));
        console2.log("salt(bytes32(tokenId)):");
        console2.logBytes32(salt);
        console2.log("liqOld:", uint256(liqOld));
        console2.log("currentTick:", int256(currentTick));

        require(liqOld > 0, "Old position liquidity=0 (wrong ticks or salt scheme?)");

        // ---------- compute NEW ticks centered around current price ----------
        int24 newTickLower = truncateTickSpacing((currentTick - rangeMultNew * tickSpacing), tickSpacing);
        int24 newTickUpper = truncateTickSpacing((currentTick + rangeMultNew * tickSpacing), tickSpacing);

        console2.log("newTickLower:", int256(newTickLower));
        console2.log("newTickUpper:", int256(newTickUpper));

        // ---------- broadcast ----------
        vm.startBroadcast(pk);

        // allowlist targets
        vault.setAllowedTarget(address(positionManager), true);
        vault.setAllowedTarget(address(permit2), true);

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

        // Ensure Permit2 approvals exist FROM THE VAULT (idempotent)
        if (!currency0.isAddressZero()) {
            vault.execute(
                t0,
                0,
                abi.encodeWithSelector(IERC20.approve.selector, address(permit2), type(uint256).max)
            );
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

        // ---------- 1) DECREASE old liquidity to vault ----------
        (bytes memory decActions, bytes[] memory decParams) =
            _decreaseLiquidityParams(
                tokenIdOld,
                uint256(liqOld),
                amount0Min,
                amount1Min,
                vaultAddr,
                hookData
            );

        bytes memory decCall = abi.encodeWithSelector(
            positionManager.modifyLiquidities.selector,
            abi.encode(decActions, decParams),
            block.timestamp + deadlineSeconds
        );

        vault.execute(address(positionManager), 0, decCall);

        // ---------- vault balances after decrease ----------
        uint256 bal0 = currency0.isAddressZero() ? vaultAddr.balance : IERC20(t0).balanceOf(vaultAddr);
        uint256 bal1 = currency1.isAddressZero() ? vaultAddr.balance : IERC20(t1).balanceOf(vaultAddr);

        console2.log("Vault balances after decrease:");
        console2.log("bal0:", bal0);
        console2.log("bal1:", bal1);
        require(bal0 > 0 || bal1 > 0, "No funds in vault after decrease");

        // ---------- 2) MINT new position to vault ----------
        uint128 liqNew = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(newTickLower),
            TickMath.getSqrtPriceAtTick(newTickUpper),
            bal0,
            bal1
        );

        uint256 amount0Max = bal0 + 1;
        uint256 amount1Max = bal1 + 1;

        uint256 tokenIdNew = positionManager.nextTokenId();
        console2.log("Next Token ID (new):", tokenIdNew);

        (bytes memory mintActions, bytes[] memory mintParams) =
            _mintLiquidityParams(
                poolKey,
                newTickLower,
                newTickUpper,
                uint256(liqNew),
                amount0Max,
                amount1Max,
                vaultAddr,
                hookData
            );

        bytes memory mintCall = abi.encodeWithSelector(
            positionManager.modifyLiquidities.selector,
            abi.encode(mintActions, mintParams),
            block.timestamp + deadlineSeconds
        );

        uint256 valueToPass = currency0.isAddressZero() ? amount0Max : 0;
        vault.execute(address(positionManager), valueToPass, mintCall);

        vm.stopBroadcast();

        console2.log("Rebalance complete.");
        console2.log("old tokenId:", tokenIdOld);
        console2.log("new tokenId:", tokenIdNew);
     }
}
