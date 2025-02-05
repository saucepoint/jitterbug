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
import {Simple} from "../../src/examples/Simple.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";

import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {Fixtures} from "../utils/Fixtures.sol";

contract SimpleTest is Test, Fixtures {
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Simple hook;
    PoolId poolId;

    address alice = makeAddr("ALICE");

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        deployAndApprovePosm(manager);

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(manager, alice); //Add all the necessary constructor arguments from the hook
        deployCodeTo("examples/Simple.sol:Simple", constructorArgs, flags);
        hook = Simple(flags);

        // Create the pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(address(hook)));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        // Transfer some tokens to alice
        currency0.transfer(alice, 1000e18);
        currency1.transfer(alice, 1000e18);
    }

    function test_simple(bool zeroForOne) public {
        // 🤔 No liquidity 🤔
        uint128 liquidity = manager.getLiquidity(poolId);
        assertEq(liquidity, 0);

        // 😏 Alice approves funds for JIT position 😏
        vm.startPrank(alice);
        IERC20(Currency.unwrap(currency0)).approve(address(hook), 1000e18);
        IERC20(Currency.unwrap(currency1)).approve(address(hook), 1000e18);
        vm.stopPrank();

        Currency inputCurrency = zeroForOne ? currency0 : currency1;
        Currency outputCurrency = zeroForOne ? currency1 : currency0;
        uint256 inputBalanceBefore = inputCurrency.balanceOfSelf();
        uint256 outputBalanceBefore = outputCurrency.balanceOfSelf();

        // Perform a test swap //
        int256 amountSpecified = -1e18;
        swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

        // 🤑 Liquidity created just in time 🤑
        assertEq(inputBalanceBefore - inputCurrency.balanceOfSelf(), 1e18);
        assertApproxEqRel(outputCurrency.balanceOfSelf() - outputBalanceBefore, 1e18, 0.05e18);
    }

    function test_gas_simple_zeroForOne() public {
        // 🤔 No liquidity 🤔
        uint128 liquidity = manager.getLiquidity(poolId);
        assertEq(liquidity, 0);

        // 😏 Alice approves funds for JIT position 😏
        vm.startPrank(alice);
        IERC20(Currency.unwrap(currency0)).approve(address(hook), 1000e18);
        IERC20(Currency.unwrap(currency1)).approve(address(hook), 1000e18);
        vm.stopPrank();

        // Perform a test swap //
        bool zeroForOne = true;
        int256 amountSpecified = -1e18;
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
        });
        PoolSwapTest.TestSettings memory settings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
        swapRouter.swap(key, params, settings, ZERO_BYTES);
        vm.snapshotGasLastCall("swap_simple_exact_input_zeroForOne");
    }
}
