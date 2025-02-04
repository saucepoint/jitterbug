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
import {EulerSwapHook} from "../../src/examples/EulerSwapHook.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {Fixtures} from "../utils/Fixtures.sol";

import {IEVault, EulerTestBase, IRMTestDefault} from "./EulerTestBase.t.sol";

contract EulerSwapHookTest is EulerTestBase, Fixtures {
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    IEVault public currency0Vault;
    IEVault public currency1Vault;

    EulerSwapHook hook;
    PoolId poolId;

    address alice = makeAddr("ALICE");

    function setUp() public override {
        super.setUp();

        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        deployAndApprovePosm(manager);

        // deploy Euler vaults
        currency0Vault = IEVault(
            factory.createProxy(
                address(0), true, abi.encodePacked(Currency.unwrap(currency0), address(oracle), unitOfAccount)
            )
        );
        currency0Vault.setHookConfig(address(0), 0);
        currency0Vault.setInterestRateModel(address(new IRMTestDefault()));
        currency0Vault.setMaxLiquidationDiscount(0.2e4);
        currency0Vault.setFeeReceiver(feeReceiver);

        currency1Vault = IEVault(
            factory.createProxy(
                address(0), true, abi.encodePacked(Currency.unwrap(currency1), address(oracle), unitOfAccount)
            )
        );
        currency1Vault.setHookConfig(address(0), 0);
        currency1Vault.setInterestRateModel(address(new IRMTestDefault()));
        currency1Vault.setMaxLiquidationDiscount(0.2e4);
        currency1Vault.setFeeReceiver(feeReceiver);

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(evc, manager, currency0Vault, currency1Vault, alice); //Add all the necessary constructor arguments from the hook
        deployCodeTo("examples/EulerSwapHook.sol:EulerSwapHook", constructorArgs, flags);
        hook = EulerSwapHook(flags);

        // Create the pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(address(hook)));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        // swap account should set the hook contract as an operator
        vm.prank(alice);
        evc.setAccountOperator(alice, address(hook), true);

        // anyone can call `configure()` on hook contract
        hook.configure();

        // Transfer some tokens to alice and deposit into Euler vaults
        _mintAndDeposit(alice, currency0Vault, 1000e18);
        _mintAndDeposit(alice, currency1Vault, 1000e18);
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

    function _mintAndDeposit(address who, IEVault vault, uint256 amount) internal {
        Currency currency = Currency.wrap(vault.asset());
        currency.transfer(who, amount);

        vm.prank(who);
        IERC20(Currency.unwrap(currency)).approve(address(vault), type(uint256).max);

        vm.prank(who);
        vault.deposit(amount, who);
    }
}
