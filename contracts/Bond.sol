// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

/**
 * @title Bond
 * @author Tanay Patil
 * @dev An interface defining a conditional bond.
 *
 * Bonds allow borrowers to create bonds in exchange for actions to be taken by a lender.
 * A bond is a locked account that can only unlocked with a corresponding bond claim.
 *
 * They can be used whenever a proxy payment is needed. For example, if a borrower would like
 * to make a payment but stay anonymous. Or another example: an instant payment between two
 * blockchains that would otherwise have a long fund transfer time.
 *
 * This contract assumes that the lenders are reading off-chain data. The communication
 * between borrower and lender is intentionally left unspecified.
 *
 * TODO: Mechanisms to do cross-chain bond lending are missing.
 * TODO: Support Ether as loan principal.
 * TODO: Support NFTs as loan principal.
 * TODO: Support arbitrary function execution with contract address and call signature
 *       rather than order struct. Users should call issue() like this:
 *       ```sol
        Bond(BOND_ADDR).issue(
            Principal(10, ERC20_ADDR),
            Order(
                targetContractAddr,
                abi.encodeWithSignature(
                    "targetFunction(string)",
                    "Hello world!"
                )
            )
        );
 *       ```
 */

import "./lib/Order.sol";
import "./lib/Principal.sol";
import "./BondClaim.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract Bond {
    address claims;

    mapping(bytes32 => bool) exists;
    mapping(bytes32 => Principal) principals;
    mapping(bytes32 => bool) settled;

    constructor(address _claims) {
        claims = _claims;
    }

    event Issued(uint256 value, address token, bytes32 orderHash);
    event Settled(bytes32 orderHash);

    /**
     * @dev Borrowers issue debt by depositing tokens and defining claim conditions.
     *
     * @param _principal - Amount and address of ERC20 tokens deposited into the bond.
     * @param _order - A struct with all the information needed for a lender to
     *                 fulfill the order and make a claim on the bond.
     */
    function issue(Principal calldata _principal, Order memory _order)
        external
        payable
    {
        require(_order.nonce != 0, "The nonce cannot be set to 0.");
        bytes32 orderHash = keccak256(abi.encode(_order));
        require(
            !exists[orderHash],
            "An order with the same hash identity already exists."
        );

        // 1) Deposit tokens into bond from borrower's account.
        bool success = IERC20(_principal.token).transferFrom(
            msg.sender,
            address(this),
            _principal.value
        );

        if (success) {
            // 2) Store the bond in storage.
            exists[orderHash] = true;
            principals[orderHash] = _principal;
            emit Issued(_principal.value, _principal.token, orderHash);
        }
    }

    /**
     * @dev Claimants settle debt by proving claim ownership and withdrawing tokens.
     *
     * Claim ownership is proven if the msg.sender == ownerOf(claimToken).
     * Since claims are implemented as NFTs, they may be traded and the claim owner may
     * not be the original lender who fulfilled the order.
     *
     * @param _orderHash - A keccack256 hash of the original order struct which is also the
     *                     tokenId of the claim NFT.
     */
    function settle(bytes32 _orderHash) external {
        require(
            !isSettled(_orderHash),
            "The bond has already been settled and the account has been withdrawn from."
        );

        // 1) Verify claimant rights.
        if (
            BondClaim(claims).isClaimed(_orderHash) &&
            msg.sender == BondClaim(claims).ownerOf(uint256(_orderHash))
        ) {
            // 2) Withdraw token to claimant.
            Principal memory principal = getPrincipal(_orderHash);
            bool success = IERC20(principal.token).transfer(
                address(this),
                principal.value
            );
            if (success) {
                emit Settled(_orderHash);

                // 3) Mark settlement of a bond.
                settled[_orderHash] = true;
            }
        }
    }

    /**
     * @dev Returns whether the bond has already been settled and the account has
     * been withdrawn from.
     *
     * @param _orderHash - A keccack256 hash of the original order struct.
     */
    function isSettled(bytes32 _orderHash) public view returns (bool ret) {
        return settled[_orderHash];
    }

    /**
     * @dev Returns the principal held by a bond.
     *
     * @param _orderHash - A keccack256 hash of the original order struct.
     */
    function getPrincipal(bytes32 _orderHash)
        public
        view
        returns (Principal memory ret)
    {
        require(exists[_orderHash], "No order with that hash identity exists.");
        return principals[_orderHash];
    }
}
