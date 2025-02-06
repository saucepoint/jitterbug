// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

import {JIT} from "../../JIT.sol";
import {JITHook} from "../../JITHook.sol";

import {EulerUtils} from "./EulerUtils.sol";

/// @title Euler Account JIT Hook
/// @notice Pulls funds from a specified Euler vaults through a specific swap account, create a JIT position, and transfers funds back to the swap account
/// @notice When user is doing exaactIn or exactOut swap, this will JIT single-sided liquidity only
/// @dev JIT position is 8% width
contract EulerSingleSidedHook is JITHook, EulerUtils {
    constructor(address evcAddr, IPoolManager poolManagerAddr, address vaultA, address vaultB, address swapAccountAddr)
        JITHook(poolManagerAddr)
        EulerUtils(evcAddr, vaultA, vaultB, swapAccountAddr)
    {}

    /// @inheritdoc JITHook
    function _pull(PoolKey calldata key, IPoolManager.SwapParams calldata swapParams)
        internal
        override
        returns (address excessRecipient, uint128 amount0, uint128 amount1)
    {
        excessRecipient = swapAccount;

        (, Currency outputCurrency, uint256 amount) = _getInputOutputAndAmount(key, swapParams);

        // transferFrom: depositor's currency0 or currency1 to the PoolManager based on currency-out from the pool
        if (outputCurrency == key.currency0) {
            amount0 = _sendToPoolManager(vault0, key.currency0, uint128(amount));
        } else {
            amount1 = _sendToPoolManager(vault1, key.currency1, uint128(amount));
        }
    }

    /// @inheritdoc JITHook
    function _recipient() internal view override returns (address) {
        return swapAccount;
    }

    /// @dev computes the tick range of the JIT position
    ///      If providing amount0 of tokens0 only, return ticks current to +8%
    ///      If providing amount1 of token1 only, return ticks -8% to current
    /// @inheritdoc JIT
    function _getTickRange(PoolKey memory poolKey, uint128 amount0, uint128 /*amount1*/, uint160 sqrtPriceX96)
        internal
        pure
        override
        returns (int24 tickLower, int24 tickUpper)
    {
        if (amount0 > 0) {
            // Only token0: provide liquidity in current to +8% range
            uint160 _sqrtPriceUpper = uint160(
                FixedPointMathLib.mulDivDown(
                    uint256(sqrtPriceX96), FixedPointMathLib.sqrt(1.08e18), FixedPointMathLib.sqrt(1e18)
                )
            );

            int24 _tickLowerUnaligned = TickMath.getTickAtSqrtPrice(sqrtPriceX96);
            int24 _tickUpperUnaligned = TickMath.getTickAtSqrtPrice(_sqrtPriceUpper);

            // align the ticks to the tick spacing
            int24 tickSpacing = poolKey.tickSpacing;
            tickLower = _alignTick(_tickLowerUnaligned, tickSpacing);
            tickUpper = _alignTick(_tickUpperUnaligned, tickSpacing);
        } else {
            // Only token1: provide liquidity in -8% to current range
            uint160 _sqrtPriceLower = uint160(
                FixedPointMathLib.mulDivDown(
                    uint256(sqrtPriceX96), FixedPointMathLib.sqrt(0.92e18), FixedPointMathLib.sqrt(1e18)
                )
            );

            int24 _tickLowerUnaligned = TickMath.getTickAtSqrtPrice(_sqrtPriceLower);
            int24 _tickUpperUnaligned = TickMath.getTickAtSqrtPrice(sqrtPriceX96);

            // align the ticks to the tick spacing
            int24 tickSpacing = poolKey.tickSpacing;
            tickLower = _alignTick(_tickLowerUnaligned, tickSpacing);
            tickUpper = _alignTick(_tickUpperUnaligned, tickSpacing);
        }
    }

    // Utility Functions

    function _sendToPoolManager(address vault, Currency currency, uint128 amount) private returns (uint128) {
        uint256 balance = _myBalance(vault);

        uint256 available;
        if (balance > 0) {
            poolManager.sync(currency);

            available = amount < balance ? amount : balance;
            _withdrawFromEuler(vault, swapAccount, swapAccount, address(poolManager), available);

            poolManager.settle();
        }

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
}
