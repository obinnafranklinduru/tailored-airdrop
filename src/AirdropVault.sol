// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAirdropVault} from "./interfaces/IAirdropVault.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title AirdropVault
 * @author BinnaDev (Obinna Franklin Duru)
 * @notice A secure, Ownable vault to hold ERC20 tokens for distribution.
 * It only allows the registered 'airdropContract' to withdraw funds.
 */
contract AirdropVault is IAirdropVault, Ownable {
    using SafeERC20 for IERC20;

    /// @notice The ERC20 token being held.
    IERC20 public immutable override token;

    /// @notice The *only* contract allowed to call `transferTo`.
    address public airdropContract;

    /// @notice Reverts if `msg.sender` is not the authorized airdrop contract.
    error NotAirdropContract();
    /// @notice Reverts if the underlying token transfer fails.

    /**
     * @param tokenAddress The address of the ERC20 token to be managed.
     * @param initialOwner The deployer/administrator of the vault.
     */
    constructor(address tokenAddress, address initialOwner) Ownable(initialOwner) {
        token = IERC20(tokenAddress);
    }

    /**
     * @notice Sets or updates the authorized airdrop contract.
     * @param _airdropContract The address of the `MerkleAirdrop` contract.
     */
    function setAirdropContract(address _airdropContract) public onlyOwner {
        airdropContract = _airdropContract;
    }

    /**
     * @notice Called by the `MerkleAirdrop` contract to distribute tokens.
     * @dev Implements the IAirdropVault interface.
     * @param to The final recipient.
     * @param amount The amount to transfer.
     */
    function transferTo(address to, uint256 amount) external override {
        if (msg.sender != airdropContract) revert NotAirdropContract();
        token.safeTransfer(to, amount);
    }

    /**
     * @notice Allows the owner to rescue/reclaim all funds if the airdrop
     * contract is misconfigured or the campaign is over.
     * @param to The address to send the remaining tokens.
     */
    function rescueFunds(address to) public onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        if (balance == 0) return; // Nothing to rescue
        token.safeTransfer(to, balance);
    }
}
