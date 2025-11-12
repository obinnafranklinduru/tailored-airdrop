// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ERC2771ForwarderMock
 * @author BinnaDev
 * @notice A minimal, lightweight mock for the ERC2771Forwarder.
 * @dev This contract is for testing purposes only. It provides an `execute`
 * function that simply forwards the `data` to the `target`.
 * The test suite is responsible for pre-prepending the sender's
 * address to the `data` to test the ERC2771Context logic.
 */
contract ERC2771ForwarderMock {
    /**
     * @notice Forwards the provided calldata to the target contract.
     * @param target The contract to call.
     * @param data The calldata (which should include the appended sender).
     */
    function execute(address target, bytes calldata data) external payable {
        (bool success, bytes memory returnData) = target.call{value: msg.value}(data);

        if (!success) {
            // Forward the revert reason from the target
            assembly {
                revert(add(returnData, 0x20), mload(returnData))
            }
        }
    }
}
