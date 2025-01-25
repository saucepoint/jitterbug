// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";

import {ImmutableState} from "v4-periphery/src/base/ImmutableState.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

abstract contract SingleJIT is ImmutableState {
    using StateLibrary for IPoolManager;

    bytes32 constant TICK_LOWER_SLOT = keccak256("tickLower");
    bytes32 constant TICK_UPPER_SLOT = keccak256("tickUpper");

    constructor(IPoolManager _manager) ImmutableState(_manager) {}

    function _getTickRange(PoolKey memory key, uint160 sqrtPriceX96)
        internal
        view
        virtual
        returns (int24 tickLower, uint160 sqrtPriceX96Lower, int24 tickUpper, uint160 sqrtPriceX96Upper);

    function _createPosition(PoolKey memory key, uint128 amount0, uint128 amount1, bytes calldata hookDataOpen)
        internal
        virtual
        returns (BalanceDelta delta, uint128 liquidity)
    {
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(key.toId());
        (int24 tickLower, uint160 sqrtPriceX96Lower, int24 tickUpper, uint160 sqrtPriceX96Upper) =
            _getTickRange(key, sqrtPriceX96);

        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96, sqrtPriceX96Lower, sqrtPriceX96Upper, amount0, amount1
        );
        _storeTicks(tickLower, tickUpper);
        (delta,) = _modifyLiquidity(key, tickLower, tickUpper, int256(uint256(liquidity)), hookDataOpen);
    }

    function _closePosition(PoolKey memory key, uint128 liquidityToClose, bytes calldata hookDataClose)
        internal
        virtual
    {
        (int24 tickLower, int24 tickUpper) = _loadTicks();
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

    function _storeTicks(int24 tickLower, int24 tickUpper) private {
        bytes32 tickLowerSlot = TICK_LOWER_SLOT;
        bytes32 tickUpperSlot = TICK_UPPER_SLOT;
        assembly {
            tstore(tickLowerSlot, tickLower)
            tstore(tickUpperSlot, tickUpper)
        }
    }

    function _loadTicks() private view returns (int24 tickLower, int24 tickUpper) {
        bytes32 tickLowerSlot = TICK_LOWER_SLOT;
        bytes32 tickUpperSlot = TICK_UPPER_SLOT;
        assembly {
            tickLower := tload(tickLowerSlot)
            tickUpper := tload(tickUpperSlot)
        }
    }
}
