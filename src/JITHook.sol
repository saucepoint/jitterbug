// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {TransientStateLibrary} from "v4-core/src/libraries/TransientStateLibrary.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {ImmutableState} from "v4-periphery/src/base/ImmutableState.sol";

import {JIT} from "./JIT.sol";

/// @title JITHook
/// @notice A minimal contract for automating JIT position provisioning via a Uniswap v4 Hook
abstract contract JITHook is JIT {
    using TransientStateLibrary for IPoolManager;

    bytes constant ZERO_BYTES = "";

    constructor(IPoolManager _poolManager) JIT(_poolManager) {
        // safety check that the hook address matches expected flags
        Hooks.validateHookPermissions(IHooks(address(this)), getHookPermissions());
    }

    /// @notice Defines the amount of tokens to be used in the JIT position
    /// @dev No tokens should be transferred into the PoolManager by this function. The afterSwap implementation, will handle token flows
    /// @param swapParams the swap params passed in during swap
    /// @return amount0 the amount of currency0 to be used for JIT position
    /// @return amount1 the amount of currency1 to be used for JIT position
    function _jitAmounts(PoolKey calldata key, IPoolManager.SwapParams calldata swapParams)
        internal
        virtual
        returns (uint128, uint128);

    /// @notice Defines logic to send external capital to the PoolManager (to settle the JIT position)
    /// @param currency The currency being sent into the PoolManager
    /// @param amount The amount of currency being sent into the PoolManager
    function _sendToPoolManager(Currency currency, uint256 amount) internal virtual;

    /// @notice The recipient of funds after the JIT position is closed
    /// @dev Inheriting contract should override and specify recipient of the JIT position
    /// @return recipient of the JIT position's funds
    function _recipient() internal view virtual returns (address);

    // TODO: restrict onlyByManager
    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata hookData)
        external
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // define the amount of tokens to be used in the JIT position
        (uint128 amount0, uint128 amount1) = _jitAmounts(key, params);

        // create JIT position
        (,, uint128 liquidity) = _createPosition(key, params, amount0, amount1, hookData);
        _storeLiquidity(liquidity);

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    // TODO: restrict onlyByManager
    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        BalanceDelta,
        bytes calldata hookData
    ) external returns (bytes4, int128) {
        // close JIT position
        uint128 liquidity = _loadLiquidity();
        _closePosition(key, liquidity, hookData);

        // TODO: possibly optimizable with a single exttload call
        int256 delta0 = poolManager.currencyDelta(address(this), key.currency0);
        int256 delta1 = poolManager.currencyDelta(address(this), key.currency1);

        // resolve the delta from opening + closing a JIT position
        if (delta0 < 0) {
            // pay currency from an arbitrary capital source to the PoolManager
            _sendToPoolManager(key.currency0, uint256(-delta0));
        } else if (delta0 > 0) {
            // transfer funds to recipient, must use ERC6909 because the swapper has not transferred ERC20 yet
            poolManager.mint(_recipient(), key.currency0.toId(), uint256(delta0));
        }

        if (delta1 < 0) {
            // pay currency from an arbitrary capital source to the PoolManager
            _sendToPoolManager(key.currency1, uint256(-delta1));
        } else if (delta1 > 0) {
            // transfer funds to recipient, must use ERC6909 because the swapper has not transferred ERC20 yet
            poolManager.mint(_recipient(), key.currency1.toId(), uint256(delta1));
        }

        return (BaseHook.afterSwap.selector, 0);
    }

    // Utility Functions

    function getHookPermissions() public pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @dev Stores the liquidity of the position (in beforeSwap)
    function _storeLiquidity(uint128 liquidity) private {
        bytes32 liquiditySlot;
        assembly {
            tstore(liquiditySlot, liquidity)
        }
    }

    /// @dev Read the liquidity of the position created in beforeSwap
    function _loadLiquidity() private view returns (uint128 liquidity) {
        bytes32 liquiditySlot;
        assembly {
            liquidity := tload(liquiditySlot)
        }
    }
}
