// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";

import {SafeCallback} from "v4-periphery/src/base/SafeCallback.sol";
import {ImmutableState} from "v4-periphery/src/base/ImmutableState.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {V4SwapRouter} from "v4-router/V4SwapRouter.sol";
import {JIT} from "./JIT.sol";

abstract contract JITRouter is V4SwapRouter, JIT {
    constructor(IPoolManager poolManager_) V4SwapRouter(poolManager_, ISignatureTransfer(address(0))) {}

    function _poolManager() internal view override returns (IPoolManager) {
        return poolManager;
    }

    function _swap(PoolKey memory poolKey, bool zeroForOne, int256 amountSpecified, bytes memory hookData)
        internal
        override
        returns (BalanceDelta)
    {
        // create position
        // (uint256 amount0, uint256 amount) = _jitAmounts();

        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: zeroForOne ? MIN : MAX
        });

        uint128 amount0;
        uint128 amount1;
        (,, uint128 liquidity) = _createPosition(poolKey, swapParams, amount0, amount1, new bytes(0));

        // facilitate swap
        BalanceDelta swapDelta = poolManager.swap(poolKey, swapParams, hookData);

        // close position
        _closePosition(poolKey, liquidity, new bytes(0));

        return swapDelta;
    }
}
