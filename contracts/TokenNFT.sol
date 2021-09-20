// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title ERC721 Token
 * @author Alejandro Garrido @xave
 * @notice Can list all stored tokens and handle URI management.
 */
contract TokenNFT is ERC721Enumerable, ERC721URIStorage, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {
        //Setup admin role for the deployer address
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    function mint(
        address mintToAdress,
        uint256 tokenId,
        string memory tkURI
    ) public onlyRole(MINTER_ROLE) {
        //TokenId is managed outside this contract
        require(!_exists(tokenId), "Token ID allready exists");

        _safeMint(mintToAdress, tokenId);
        _setTokenURI(tokenId, tkURI);
    }

    /*All the OVERRIDDEN functions below*/

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, ERC721Enumerable, AccessControl)
        returns (bool)
    {
        //Call all parents on the inheritance tree
        return super.supportsInterface(interfaceId);
    }

    function _burn(uint256 tokenId)
        internal
        virtual
        override(ERC721, ERC721URIStorage)
    {
        //Call all parents on the inheritance tree.
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        //Not using "super". Call only ERC721URIStorage.
        return ERC721URIStorage.tokenURI(tokenId);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override(ERC721, ERC721Enumerable) {
        //Not using "super". Call only ERC721Enumerable.
        ERC721Enumerable._beforeTokenTransfer(from, to, tokenId);
    }
}
