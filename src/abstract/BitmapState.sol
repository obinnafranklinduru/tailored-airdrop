// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";

/**
 * @title BitmapState
 * @author BinnaDev (Obinna Franklin Duru)
 * @notice Abstract contract for gas-efficiently tracking claimed indices using a bitmap.
 * This is the core of our replay protection for indexed claims.
 */
abstract contract BitmapState {
    using BitMaps for BitMaps.BitMap;

    // The bitmap storage slot.
    BitMaps.BitMap private _claimed;

    error AlreadyClaimed(uint256 index);

    /**
     * @dev Internal function to mark an index as claimed.
     * Reverts if the index has already been claimed.
     * This follows the Checks-Effects pattern.
     * @param index The index to mark as claimed (e.g., from the Merkle tree).
     */
    function _setClaimed(uint256 index) internal {
        if (_claimed.get(index)) revert AlreadyClaimed(index);
        _claimed.set(index);
    }

    /**
     * @dev Public view function to check if an index has been claimed.
     * @param index The index to check.
     * @return bool True if the index is claimed, false otherwise.
     */
    function isClaimed(uint256 index) public view returns (bool) {
        return _claimed.get(index);
    }
}
