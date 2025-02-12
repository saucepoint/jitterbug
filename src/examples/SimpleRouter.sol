// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

import {JIT} from "../JIT.sol";
import {JITRouter} from "../JITRouter.sol";

/// @title Simple JIT Hook
/// @notice Pulls funds from a specified address, create a JIT position, and transfers funds back to the deployer
/// @dev JIT position is +/- 10% of the spot price
contract SimpleJITRouter is JITRouter {
    /// @dev Depositor should ERC20.approve this address
    address depositor;

    constructor(IPoolManager _poolManager, address _depositor) JITRouter(_poolManager) {
        depositor = _depositor;
    }

    /// @dev Defines the amount of tokens to be used in the JIT position
    /// @inheritdoc JITRouter
    function _jitAmounts(PoolKey memory, /*key*/ IPoolManager.SwapParams memory /*swapParams*/ )
        internal
        pure
        override
        returns (uint128 amount0, uint128 amount1)
    {
        amount0 = uint128(100e18);
        amount1 = uint128(100e18);
    }

    /// @dev Example logic for sending money to PoolManager, from an arbitrary capital source (EOA)
    /// @inheritdoc JITRouter
    function _sendToPoolManager(Currency currency, uint256 amount) internal override {
        poolManager.sync(currency);
        IERC20(Currency.unwrap(currency)).transferFrom(depositor, address(poolManager), amount);
        poolManager.settle();
    }

    /// @dev Defines the recipient of the JIT position once its closed
    /// @inheritdoc JITRouter
    function _recipient() internal view override returns (address) {
        return depositor;
    }

    /// @dev computes the tick range of the JIT position by returning ticks as +/- 10% of spot price
    /// @inheritdoc JIT
    function _getTickRange(
        PoolKey memory poolKey,
        IPoolManager.SwapParams memory, /*swapParams*/
        uint128, /*amount0*/
        uint128, /*amount1*/
        uint160 sqrtPriceX96
    ) internal pure override returns (int24 tickLower, int24 tickUpper) {
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

    /// @dev NOT PRODUCTION READY. Incorrectly rounds ticks to 0
    /// Should be rounding consistently either towards spot price or away from spot price, regardless of sign
    function _alignTick(int24 tick, int24 tickSpacing) internal pure returns (int24) {
        return (tick / tickSpacing) * tickSpacing;
    }
}
