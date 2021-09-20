// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TokenNFT.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title NFT Sales Proxy
 * @author Alejandro Garrido @xave
 * @notice Handles the exchange between non fungible tokens (ERC721) and
 * native currency (eth).
 * NFT creators can choose to:
 *  - Sale NFTs using the lazy minting method.
 *  - Mint their NFTs
 *  - Sale an NFT that is already minted
 * The eth the buyer pays for the NFT, can be split into more than
 * one recipient.
 * Every sale and its payment distribution must be previously approved
 * and signed by the NFT's owner and _trustedSigner.
 */
contract SalesProxy is AccessControl, ReentrancyGuard {
    //Address of admin signer
    address private _trustedSigner;

    //Lengh of the tokenId prefix. There is one unique prefix per owmer
    uint8 public constant OWNER_TOKEN_ID_PREFIX_LENGTH = 12;

    receive() external payable {}

    constructor() {
        //Deployer is the default trusted signer
        _trustedSigner = msg.sender;

        //Setup admin role to the deployer
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setTrustedSigner(address signatureAddress)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _trustedSigner = signatureAddress;
    }

    function getTrustedSigner()
        public
        view
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (address)
    {
        return _trustedSigner;
    }

    /**
     * @notice Mint a token in TokenNFT
     * @param tokenAddress The TokenNFT address
     * @param mintToAddress Address to mint the token
     * @param tokenId Token ID
     * @param tkURI token URI
     */
    function mintToken(
        address tokenAddress,
        address mintToAddress,
        uint256 tokenId,
        string memory tkURI
    ) public {
        string memory sTokenId = Strings.toString(tokenId);

        require(
            bytes(sTokenId).length > OWNER_TOKEN_ID_PREFIX_LENGTH,
            "TokenId is too short"
        );

        //Validate the tokenId prefix
        require(
            keccak256(abi.encodePacked(_parseTokenIdPrefix(mintToAddress))) ==
                keccak256(abi.encodePacked(_getTokenIdPrefix(sTokenId))),
            "The tokenId prefix is not valid for mintToAddress"
        );

        // Mint the token
        // Proxy must have MINTER_ROLE granted on TokenNFT deployed 
        // at tokenAddrerss
        TokenNFT(tokenAddress).mint(mintToAddress, tokenId, tkURI);
    }

    /**
     * @dev Buy an NFT token with native (eth). Can use the lazy minting
     * technique. Distribute the payment among pymtDistAddress.
     * Validate _trustedSigner and seller's signatures. 
     * @param tokenAddress The NFT token address.
     * @param tokenId Token ID minted in tokenAddress or to be minted if using
     * lazy minting.
     * @param pymtDistAddress Array with all the addresses to transfer eth.
     * @param pymtDistAmt Array with the amount (in wei) to transfer to each
     * address in pymtDistAddress, matched by their index number.
     * @param sellerSignature Seller's signature of the first 4 parameters
     * on this fucntion plus this Proxy address. Proxy address goes after tokenId.
     * @param adminSignature Admin signature of the same parameters signed 
     * by sellerSignature.
     * @param isMinted Indicates whether the tokenId should be treated as
     * minted or not. If false, lazy minting will be used.
     */
    function buyNFTWithNative(
        address tokenAddress,
        uint256 tokenId,
        address[] calldata pymtDistAddress,
        uint256[] calldata pymtDistAmt,
        bytes memory sellerSignature,
        bytes memory adminSignature,
        bool isMinted,
        string memory tokenURI
    ) public payable nonReentrant {
        // Verify adminSignature and get sellerAddress form sellerSignature.
        address sellerAddress = _verifySignature(
            tokenAddress,
            tokenId,
            address(this),
            pymtDistAddress,
            pymtDistAmt,
            sellerSignature,
            adminSignature
        );

        if (isMinted) {
            // if minted, check token info
            address tokenOwner = IERC721(tokenAddress).ownerOf(tokenId);
            require(
                tokenOwner == sellerAddress,
                "Seller from signature does not own the token ID"
            );
            require(
                tokenOwner != msg.sender,
                "The buyer already owns the token ID"
            );
            require(
                IERC721(tokenAddress).getApproved(tokenId) == address(this) ||
                    IERC721(tokenAddress).isApprovedForAll(
                        tokenOwner,
                        address(this)
                    ),
                "Proxy does not have approval to transfer the token"
            );
        } else {
            // if not minted, check if the token ID prefix corresponds to the sellerAddress
            require(
                keccak256(
                    abi.encodePacked(
                        _getTokenIdPrefix(Strings.toString(tokenId))
                    )
                ) ==
                    keccak256(
                        abi.encodePacked(_parseTokenIdPrefix(sellerAddress))
                    ),
                "Token ID does not match the seller's signature"
            );
        }

        require(
            pymtDistAddress.length > 0 &&
                pymtDistAddress.length == pymtDistAmt.length,
            "pymtDistAddress and pymtDistAmt must be the same size and have at least one item"
        );

        // Transfer the payment to each account
        uint256 totalAmt = 0;
        for (uint8 i = 0; i < pymtDistAddress.length; i++) {
            totalAmt += pymtDistAmt[i];

            require(pymtDistAddress[i] != address(0), "Invalid payee address");
            require(pymtDistAmt[i] > 0, "Amount cannot be 0");

            // Transfer wei
            Address.sendValue(payable(pymtDistAddress[i]), pymtDistAmt[i]);
        }

        require(
            msg.value == totalAmt,
            "The sum of the payment dritribution does not match sender's value"
        );

        if (isMinted) {
            // Trasfer the NFT to the buyer
            uint256 _tokenId = tokenId;
            address tokenOwner = IERC721(tokenAddress).ownerOf(_tokenId);
            IERC721(tokenAddress).safeTransferFrom(
                tokenOwner,
                msg.sender,
                _tokenId
            );
        } else {
            // Mint the token to the buyer
            TokenNFT(tokenAddress).mint(msg.sender, tokenId, tokenURI);
        }
    }

    /**
     * @dev Validates that all theparameters, when encoded and hashed, match the
     * _trustedSigner signature. Use the same digest with the seller's signature,
     * to recover the seller's address that signed the message.  
     */
    function _verifySignature(
        address tokenAddress,
        uint256 tokenId,
        address proxyAddress,
        address[] calldata pymtDistAddress,
        uint256[] calldata pymtDistAmt,
        bytes memory sellerSignature,
        bytes memory adminSignature
    ) private view returns (address) {
        bytes memory encodedParam = abi.encodePacked(
            tokenAddress,
            tokenId,
            proxyAddress,
            pymtDistAddress,
            pymtDistAmt
        );

        bytes32 digest = ECDSA.toEthSignedMessageHash(keccak256(encodedParam));

        require(
            ECDSA.recover(digest, adminSignature) == _trustedSigner,
            "Invalid admin signature"
        );

        return ECDSA.recover(digest, sellerSignature);
    }

    /**
     * @dev Calculates tokenID prefix for the given address.
     * Hash _address with keccak256 and convert each resulting byte into numbers.
     * Returns those numbers as a string sliced to OWNER_TOKEN_ID_PREFIX_LENGTH
     */
    function _parseTokenIdPrefix(address _address)
        private
        pure
        returns (string memory)
    {
        bytes memory bstr;
        bytes memory bstrSliced;

        // Hash the address
        bytes32 b = keccak256(abi.encodePacked(_address));

        // Read each byte from the hash, convert it to unit8 and make a string of
        // numeric characters with lenth == OWNER_TOKEN_ID_PREFIX_LENGTH
        // The expression uint8(b[index]) can return more than 1 digit, so
        // most likely the loop will exit at "break"
        for (uint256 index = 0; index < OWNER_TOKEN_ID_PREFIX_LENGTH; index++) {
            bstr = bytes.concat(bstr, bytes(Strings.toString(uint8(b[index]))));
            
            // if it is too long, remove everything over OWNER_TOKEN_ID_PREFIX_LENGTH
            if (bstr.length > OWNER_TOKEN_ID_PREFIX_LENGTH) {
                for (uint8 i = 0; i < OWNER_TOKEN_ID_PREFIX_LENGTH; i++) {
                    bstrSliced = bytes.concat(bstrSliced, bstr[i]);
                }

                break;
            }
        }
        return string(bstrSliced);
    }

    /**
     * @dev Slice tokenId to the length of OWNER_TOKEN_ID_PREFIX_LENGTH.
     * If tokenId is shorter, then returns an empty string
     * Note: Cannot use Solidity native slice (ie: tokenId[0:12]) because is
     * not available for bytes allocated on memory, yet. Only works for calldata.
     */
    function _getTokenIdPrefix(string memory tokenId)
        private
        pure
        returns (string memory)
    {
        bytes memory bTokenId = abi.encodePacked(tokenId);
        bytes memory bTokenIdPrefix;

        //tokenId length must be at least OWNER_TOKEN_ID_PREFIX_LENGTH
        if (bTokenId.length < OWNER_TOKEN_ID_PREFIX_LENGTH) {
            return string("");
        }

        for (uint8 i = 0; i < OWNER_TOKEN_ID_PREFIX_LENGTH; i++) {
            bTokenIdPrefix = bytes.concat(bTokenIdPrefix, bTokenId[i]);
        }
        return string(bTokenIdPrefix);
    }
}
