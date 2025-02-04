// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/console2.sol";

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IEVC} from "evc/interfaces/IEthereumVaultConnector.sol";
import {IEVault, IBorrowing, IERC4626, IRiskManager} from "evk/EVault/IEVault.sol";

import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {CustomRevert} from "v4-core/src/libraries/CustomRevert.sol";
import {EVCUtil} from "evc/utils/EVCUtil.sol";

import {JIT} from "../JIT.sol";
import {JITHook} from "../JITHook.sol";

contract EulerSwapHook is JITHook, EVCUtil {
    using CustomRevert for bytes4;

    address public immutable vault0;
    address public immutable vault1;
    address public immutable asset0;
    address public immutable asset1;
    address public immutable swapAccount;

    error UnsupportedPair();
    error DifferentEVC();

    constructor(address evcAddr, IPoolManager _poolManager, address vaultA, address vaultB, address swapAccountAddr)
        JITHook(_poolManager)
        EVCUtil(evcAddr)
    {
        address vaultAEvc = IEVault(vaultA).EVC();
        if (vaultAEvc != IEVault(vaultB).EVC()) DifferentEVC.selector.revertWith();
        if (vaultAEvc != evcAddr) DifferentEVC.selector.revertWith();

        address assetA = IEVault(vaultA).asset();
        address assetB = IEVault(vaultB).asset();
        if (assetA == assetB) UnsupportedPair.selector.revertWith();

        swapAccount = swapAccountAddr;

        (vault0, asset0, vault1, asset1) =
            assetA < assetB ? (vaultA, assetA, vaultB, assetB) : (vaultB, assetB, vaultA, assetA);
    }

    /// @dev Call *after* installing as operator
    function configure() external {
        IEVC(evc).enableCollateral(swapAccount, vault0);
        IEVC(evc).enableCollateral(swapAccount, vault1);
    }

    /// @inheritdoc JITHook
    function _pull(PoolKey calldata key, IPoolManager.SwapParams calldata params)
        internal
        override
        returns (address excessRecipient, uint128 amount0, uint128 amount1)
    {
        excessRecipient = swapAccount;

        amount0 = uint128(100e18);
        amount1 = uint128(100e18);

        // transferFrom: depositor's currency0 and currency1 to the PoolManager
        amount0 = _sendToPoolManager(vault0, key.currency0, amount0);
        amount1 = _sendToPoolManager(vault1, key.currency1, amount1);
    }

    /// @inheritdoc JITHook
    function _recipient() internal view override returns (address) {
        return swapAccount;
    }

    /// @dev computes the tick range of the JIT position by returning ticks as +/- 10% of spot price
    /// @inheritdoc JIT
    function _getTickRange(PoolKey memory poolKey, uint160 sqrtPriceX96)
        internal
        pure
        override
        returns (int24 tickLower, int24 tickUpper)
    {
        // calculating sqrt(price * 0.9e18/1e18) * Q96 is the same as
        // (sqrt(price) * Q96) * (sqrt(0.9e18/1e18))
        // (sqrt(price) * Q96) * (sqrt(0.9e18) / sqrt(1e18))
        uint160 _sqrtPriceLower = uint160(
            FixedPointMathLib.mulDivDown(
                uint256(sqrtPriceX96), FixedPointMathLib.sqrt(0.9e18), FixedPointMathLib.sqrt(1e18)
            )
        );

        // calculating sqrt(price * 1.1) * Q96 is the same as
        // (sqrt(price) * Q96) * (sqrt(1.1e18/1e18))
        // (sqrt(price) * Q96) * (sqrt(1.1e18) / sqrt(1e18))
        uint160 _sqrtPriceUpper = uint160(
            FixedPointMathLib.mulDivDown(
                uint256(sqrtPriceX96), FixedPointMathLib.sqrt(1.1e18), FixedPointMathLib.sqrt(1e18)
            )
        );

        int24 _tickLowerUnaligned = TickMath.getTickAtSqrtPrice(_sqrtPriceLower);
        int24 _tickUpperUnaligned = TickMath.getTickAtSqrtPrice(_sqrtPriceUpper);

        // align the ticks to the tick spacing
        int24 tickSpacing = poolKey.tickSpacing;
        tickLower = _alignTick(_tickLowerUnaligned, tickSpacing);
        tickUpper = _alignTick(_tickUpperUnaligned, tickSpacing);
    }

    // Utility Functions

    function _sendToPoolManager(address vault, Currency currency, uint128 amount) private returns (uint128) {
        uint256 balance = _myBalance(vault);

        console2.log("balance", balance);
        console2.log("amount", amount);

        uint256 available;
        if (balance > 0) {
            poolManager.sync(currency);

            available = amount < balance ? amount : balance;
            IEVC(evc).call(
                vault, swapAccount, 0, abi.encodeCall(IERC4626.withdraw, (available, address(poolManager), swapAccount))
            );

            poolManager.settle();
        }

        // console2.log("available", available);
        // console2.log("hook balance", IERC20(IEVault(vault).asset()).balanceOf(address(this)));

        // poolManager.sync(currency);
        // IERC20(Currency.unwrap(currency)).transfer(address(poolManager), available);
        // poolManager.settle();

        return uint128(available);
    }

    /// @dev NOT PRODUCTION READY. Incorrectly rounds ticks to 0
    /// Should be rounding consistently either towards spot price or away from spot price, regardless of sign
    function _alignTick(int24 tick, int24 tickSpacing) internal pure returns (int24) {
        return (tick / tickSpacing) * tickSpacing;
    }

    function _getInputOutputAndAmount(PoolKey calldata key, IPoolManager.SwapParams calldata params)
        internal
        pure
        returns (Currency input, Currency output, uint256 amount)
    {
        (input, output) = params.zeroForOne ? (key.currency0, key.currency1) : (key.currency1, key.currency0);

        amount = params.amountSpecified < 0 ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);
    }

    function _myBalance(address vault) internal view returns (uint256) {
        uint256 shares = IEVault(vault).balanceOf(swapAccount);
        return shares == 0 ? 0 : IEVault(vault).convertToAssets(shares);
    }
}
