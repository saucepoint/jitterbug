// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

library SwapParser {
    /// @notice Determine the input, output currencies and the amount
    /// @param key The pool key
    /// @param swapParams The IPoolManager.SwapParams of the current swap. Includes trade size and direction
    function getInputOutputAndAmount(PoolKey calldata key, IPoolManager.SwapParams calldata swapParams)
        internal
        pure
        returns (Currency input, Currency output, uint256 amount)
    {
        (input, output) = swapParams.zeroForOne ? (key.currency0, key.currency1) : (key.currency1, key.currency0);

        amount =
            swapParams.amountSpecified < 0 ? uint256(-swapParams.amountSpecified) : uint256(swapParams.amountSpecified);
    }
}
