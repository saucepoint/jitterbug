// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

import {SafeCallback} from "v4-periphery/src/base/SafeCallback.sol";
import {ImmutableState} from "v4-periphery/src/base/ImmutableState.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {V4SwapRouter} from "v4-router/V4SwapRouter.sol";
import {JIT} from "./JIT.sol";

abstract contract JITRouter is V4SwapRouter, JIT {
    constructor(IPoolManager poolManager_) V4SwapRouter(poolManager_, ISignatureTransfer(address(0))) {}

    /// @notice Defines the amount of tokens to be used in the JIT position
    /// @dev No tokens should be transferred into the PoolManager by this function. The afterSwap implementation, will handle token flows
    /// @param swapParams the swap params passed in during swap
    /// @return amount0 the amount of currency0 pulled into the JIT position
    /// @return amount1 the amount of currency1 pulled into the JIT position
    function _jitAmounts(PoolKey memory key, IPoolManager.SwapParams memory swapParams)
        internal
        virtual
        returns (uint128, uint128);

    /// @notice Defines logic to send external capital to the PoolManager, to settle the JIT position
    /// @param currency The currency being sent into the PoolManager
    /// @param amount The amount of currency being sent into the PoolManager
    function _sendToPoolManager(Currency currency, uint256 amount) internal virtual;

    /// @notice The recipient of funds after the JIT position is closed
    /// @dev Inheriting contract should override and specify recipient of the JIT position
    /// @return recipient of the JIT position's funds
    function _recipient() internal view virtual returns (address);

    function _poolManager() internal view override returns (IPoolManager) {
        return poolManager;
    }

    function _swap(PoolKey memory poolKey, bool zeroForOne, int256 amountSpecified, bytes memory hookData)
        internal
        override
        returns (BalanceDelta)
    {
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: zeroForOne ? MIN : MAX
        });

        // create position
        (uint128 amount0, uint128 amount1) = _jitAmounts(poolKey, swapParams);
        (BalanceDelta deltaOpen,, uint128 liquidity) =
            _createPosition(poolKey, swapParams, amount0, amount1, new bytes(0));

        // facilitate swap
        BalanceDelta swapDelta = poolManager.swap(poolKey, swapParams, hookData);

        // close position
        (BalanceDelta deltaClose,) = _closePosition(poolKey, liquidity, new bytes(0));

        // resolve deltas for the JIT position, and NOT the swap delta
        BalanceDelta jitDelta = deltaOpen + deltaClose;
        _resolveDelta(jitDelta, poolKey.currency0, poolKey.currency1);

        return swapDelta;
    }

    function _resolveDelta(BalanceDelta delta, Currency currency0, Currency currency1) private {
        int128 delta0 = delta.amount0();
        int128 delta1 = delta.amount1();
        if (delta0 < 0) {
            // pay currency
            _sendToPoolManager(currency0, uint256(-int256(delta0)));
        } else if (delta0 > 0) {
            // transfer funds to recipient, must use ERC6909 because the swapper has not transferred ERC20 yet
            poolManager.mint(_recipient(), currency0.toId(), uint256(int256(delta0)));
        }

        if (delta1 < 0) {
            // pay currency
            _sendToPoolManager(currency1, uint256(-int256(delta1)));
        } else if (delta1 > 0) {
            // transfer funds to recipient, must use ERC6909 because the swapper has not transferred ERC20 yet
            poolManager.mint(_recipient(), currency1.toId(), uint256(int256(delta1)));
        }
    }
}
