// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IAirdropVault
 * @author BinnaDev (Obinna Franklin Duru)
 * @notice Interface for a simple, permissioned token vault.
 * The vault holds all assets and allows a designated "airdropContract"
 * to call `transferTo` for distribution.
 */
interface IAirdropVault {
    /**
     * @notice Returns the address of the ERC20 token held by the vault.
     */
    function token() external view returns (IERC20);

    /**
     * @notice Called by the Airdrop contract to distribute tokens.
     * @dev This function must implement a check to ensure
     * `msg.sender` is the authorized `airdropContract`.
     * @param to The final recipient of the tokens.
     * @param amount The amount of tokens to send.
     */
    function transferTo(address to, uint256 amount) external;
}
