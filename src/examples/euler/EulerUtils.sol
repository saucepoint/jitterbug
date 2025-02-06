// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEVC} from "evc/interfaces/IEthereumVaultConnector.sol";
import {IEVault, IBorrowing, IERC4626, IRiskManager} from "evk/EVault/IEVault.sol";
import {EVCUtil} from "evc/utils/EVCUtil.sol";
import {CustomRevert} from "v4-core/src/libraries/CustomRevert.sol";

contract EulerUtils is EVCUtil {
    using CustomRevert for bytes4;

    error UnsupportedPair();
    error DifferentEVC();

    // Euler's vaults
    address public immutable vault0;
    address public immutable vault1;
    // Vault's assets
    address public immutable asset0;
    address public immutable asset1;
    // Account address that has liquidity into Euler vaults
    address public immutable swapAccount;

    constructor(address evcAddr, address vaultA, address vaultB, address swapAccountAddr) EVCUtil(evcAddr) {
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

    function _withdrawFromEuler(
        address vault,
        address onBehalfOfAccount,
        address owner,
        address receiver,
        uint256 amount
    ) internal {
        IEVC(evc).call(vault, onBehalfOfAccount, 0, abi.encodeCall(IERC4626.withdraw, (amount, receiver, owner)));
    }

    function _myBalance(address vault) internal view returns (uint256) {
        uint256 shares = IEVault(vault).balanceOf(swapAccount);
        return shares == 0 ? 0 : IEVault(vault).convertToAssets(shares);
    }
}
