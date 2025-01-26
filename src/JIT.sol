// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";

import {ImmutableState} from "v4-periphery/src/base/ImmutableState.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

abstract contract JIT is ImmutableState {
    using StateLibrary for IPoolManager;

    bytes32 constant TICK_LOWER_SLOT = keccak256("tickLower");
    bytes32 constant TICK_UPPER_SLOT = keccak256("tickUpper");

    constructor(IPoolManager _manager) ImmutableState(_manager) {}

    /// @notice Determine the tick range for the JIT position
    /// @param key The pool key
    /// @param sqrtPriceX96 The current sqrt price of the pool
    /// @return tickLower The lower tick of the JIT position
    /// @return tickUpper The upper tick of the JIT position
    function _getTickRange(PoolKey memory key, uint160 sqrtPriceX96)
        internal
        view
        virtual
        returns (int24 tickLower, int24 tickUpper);

    function _createPosition(PoolKey memory key, uint128 amount0, uint128 amount1, bytes calldata hookDataOpen)
        internal
        virtual
        returns (BalanceDelta delta, BalanceDelta feesAccrued, uint128 liquidity)
    {
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(key.toId());
        (int24 tickLower, int24 tickUpper) = _getTickRange(key, sqrtPriceX96);

        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0,
            amount1
        );
        _storeTicks(tickLower, tickUpper);
        (delta, feesAccrued) = _modifyLiquidity(key, tickLower, tickUpper, int256(uint256(liquidity)), hookDataOpen);
    }

    function _closePosition(PoolKey memory key, uint128 liquidityToClose, bytes calldata hookDataClose)
        internal
        virtual
        returns (BalanceDelta delta, BalanceDelta feesAccrued)
    {
        (int24 tickLower, int24 tickUpper) = _loadTicks();
        (delta, feesAccrued) =
            _modifyLiquidity(key, tickLower, tickUpper, -int256(uint256(liquidityToClose)), hookDataClose);
    }

    function _modifyLiquidity(
        PoolKey memory key,
        int24 tickLower,
        int24 tickUpper,
        int256 liquidityDelta,
        bytes calldata hookData
    ) internal virtual returns (BalanceDelta totalDelta, BalanceDelta feesAccrued) {
        (totalDelta, feesAccrued) = poolManager.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: liquidityDelta,
                salt: bytes32(0)
            }),
            hookData
        );
    }

    /// @dev Store the tick range of the JIT position
    function _storeTicks(int24 tickLower, int24 tickUpper) private {
        bytes32 tickLowerSlot = TICK_LOWER_SLOT;
        bytes32 tickUpperSlot = TICK_UPPER_SLOT;
        assembly {
            tstore(tickLowerSlot, tickLower)
            tstore(tickUpperSlot, tickUpper)
        }
    }

    /// @dev Load the tick range of the JIT position, to be used to close the position
    function _loadTicks() private view returns (int24 tickLower, int24 tickUpper) {
        bytes32 tickLowerSlot = TICK_LOWER_SLOT;
        bytes32 tickUpperSlot = TICK_UPPER_SLOT;
        assembly {
            tickLower := tload(tickLowerSlot)
            tickUpper := tload(tickUpperSlot)
        }
    }
}
