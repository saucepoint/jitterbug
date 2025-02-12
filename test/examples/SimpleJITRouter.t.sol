// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {SimpleJITRouter} from "../../src/examples/SimpleRouter.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";

import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {Fixtures} from "../utils/Fixtures.sol";

contract SimpleJITRouterTest is Test, Fixtures {
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    SimpleJITRouter jitRouter;
    PoolId poolId;

    address alice = makeAddr("ALICE");

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        deployAndApprovePosm(manager);

        // Deploy the JIT router
        jitRouter = new SimpleJITRouter(manager, alice);

        // approve the jit router
        IERC20(Currency.unwrap(currency0)).approve(address(jitRouter), 1000e18);
        IERC20(Currency.unwrap(currency1)).approve(address(jitRouter), 1000e18);

        // Create the pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(address(0)));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        // Transfer some tokens to alice
        currency0.transfer(alice, 1000e18);
        currency1.transfer(alice, 1000e18);
    }

    function test_simple_jit_router(bool zeroForOne) public {
        // 🤔 No liquidity 🤔
        uint128 liquidity = manager.getLiquidity(poolId);
        assertEq(liquidity, 0);

        // 😏 Alice approves funds for JIT position 😏
        vm.startPrank(alice);
        IERC20(Currency.unwrap(currency0)).approve(address(jitRouter), 1000e18);
        IERC20(Currency.unwrap(currency1)).approve(address(jitRouter), 1000e18);
        vm.stopPrank();

        Currency inputCurrency = zeroForOne ? currency0 : currency1;
        Currency outputCurrency = zeroForOne ? currency1 : currency0;
        uint256 inputBalanceBefore = inputCurrency.balanceOfSelf();
        uint256 outputBalanceBefore = outputCurrency.balanceOfSelf();

        // Perform a test swap //
        uint256 amountIn = 1e18; // amount of input tokens
        uint256 amountOutMin = 0.99e18; // minimum amount of output tokens, otherwise revert
        uint256 deadline = block.timestamp + 60; // deadline for the transaction to be mined
        jitRouter.swapExactTokensForTokens(amountIn, amountOutMin, zeroForOne, key, ZERO_BYTES, address(this), deadline);

        // 🤑 Liquidity created just in time 🤑
        assertEq(inputBalanceBefore - inputCurrency.balanceOfSelf(), 1e18);
        assertApproxEqRel(outputCurrency.balanceOfSelf() - outputBalanceBefore, 1e18, 0.05e18);
    }

    function test_gas_simpleRouter_zeroForOne() public {
        // 🤔 No liquidity 🤔
        uint128 liquidity = manager.getLiquidity(poolId);
        assertEq(liquidity, 0);

        // 😏 Alice approves funds for JIT position 😏
        vm.startPrank(alice);
        IERC20(Currency.unwrap(currency0)).approve(address(jitRouter), 1000e18);
        IERC20(Currency.unwrap(currency1)).approve(address(jitRouter), 1000e18);
        vm.stopPrank();

        // Perform a test swap //
        bool zeroForOne = true;
        uint256 amountIn = 1e18; // amount of input tokens
        uint256 amountOutMin = 0.99e18; // minimum amount of output tokens, otherwise revert
        uint256 deadline = block.timestamp + 60; // deadline for the transaction to be mined
        jitRouter.swapExactTokensForTokens(amountIn, amountOutMin, zeroForOne, key, ZERO_BYTES, address(this), deadline);
        vm.snapshotGasLastCall("jitRouter_exactInput_zeroForOne");
    }
}
