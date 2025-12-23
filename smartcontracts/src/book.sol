// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.4.0
pragma solidity 0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title Book
 * @dev ERC1155 token for book editions where:
 *      - edition = edition number
 *      - item = item number within the edition
 *      Each book item is unique (internal amount is always 1)
 *      example base url https://jeffprestes.github.io/bookerc1155/metadata/
 */
contract Book is ERC1155, Ownable {
    using Strings for uint256;

    // Base URI for metadata
    string private _baseURI;

    // Mapping from token ID to custom URI
    mapping(uint256 => string) private _tokenURIs;

    // Edition multiplier for encoding token IDs (edition * EDITION_MULTIPLIER + item)
    uint256 public constant EDITION_MULTIPLIER = 1_000_000;

    // Events
    event BookMinted(address indexed to, uint256 indexed edition, uint256 indexed item);
    event BookBatchMinted(address indexed to, uint256[] editions, uint256[] items);
    event TokenURISet(uint256 indexed tokenId, string uri);

    constructor(address initialOwner, string memory baseURI_)
        ERC1155(baseURI_)
        Ownable(initialOwner)
    {
        _baseURI = baseURI_;
    }

    /**
     * @dev Encodes edition and item into a single token ID
     * @param edition The edition number
     * @param item The item number within the edition
     * @return tokenId The encoded token ID
     */
    function encodeTokenId(uint256 edition, uint256 item) public pure returns (uint256) {
        require(item < EDITION_MULTIPLIER, "Item number too large");
        return edition * EDITION_MULTIPLIER + item;
    }

    /**
     * @dev Decodes a token ID into edition and item
     * @param tokenId The token ID to decode
     * @return edition The edition number
     * @return item The item number
     */
    function decodeTokenId(uint256 tokenId) public pure returns (uint256 edition, uint256 item) {
        edition = tokenId / EDITION_MULTIPLIER;
        item = tokenId % EDITION_MULTIPLIER;
    }

    /**
     * @dev Returns the URI for a token ID
     */
    function uri(uint256 tokenId) public view override returns (string memory) {
        string memory tokenURI = _tokenURIs[tokenId];
        
        if (bytes(tokenURI).length > 0) {
            return tokenURI;
        }
        
        return string(abi.encodePacked(_baseURI, tokenId.toString(), ".json"));
    }

    /**
     * @dev Returns the URI for a book using edition and item
     * @param edition The edition number
     * @param item The item number within the edition
     */
    function bookURI(uint256 edition, uint256 item) public view returns (string memory) {
        uint256 tokenId = encodeTokenId(edition, item);
        return uri(tokenId);
    }

    /**
     * @dev Sets the base URI for all tokens
     */
    function setBaseURI(string memory newBaseURI) public onlyOwner {
        _baseURI = newBaseURI;
        _setURI(newBaseURI);
    }

    /**
     * @dev Sets a custom URI for a specific token ID
     */
    function setTokenURI(uint256 tokenId, string memory tokenURI) public onlyOwner {
        _tokenURIs[tokenId] = tokenURI;
        emit TokenURISet(tokenId, tokenURI);
    }

    /**
     * @dev Sets a custom URI using edition and item
     */
    function setTokenURI(uint256 edition, uint256 item, string memory tokenURI) public onlyOwner {
        uint256 tokenId = encodeTokenId(edition, item);
        _tokenURIs[tokenId] = tokenURI;
        emit TokenURISet(tokenId, tokenURI);
    }

    /**
     * @dev Generates the token URI from baseURI and tokenId
     */
    function _generateTokenURI(uint256 tokenId) internal view returns (string memory) {
        return string(abi.encodePacked(_baseURI, tokenId.toString(), ".json"));
    }

    /**
     * @dev Mints a unique book token and automatically sets its URI
     * @param to Recipient address
     * @param edition Edition number
     * @param item Item number within the edition
     */
    function mint(address to, uint256 edition, uint256 item) public onlyOwner {
        uint256 tokenId = encodeTokenId(edition, item);
        string memory tokenURI = _generateTokenURI(tokenId);
        _mint(to, tokenId, 1, "");
        _tokenURIs[tokenId] = tokenURI;
        emit TokenURISet(tokenId, tokenURI);
        emit BookMinted(to, edition, item);
    }

    /**
     * @dev Mints multiple unique book tokens and automatically sets their URIs
     * @param to Recipient address
     * @param editions Array of edition numbers
     * @param items Array of item numbers
     */
    function mintBatch(address to, uint256[] memory editions, uint256[] memory items) public onlyOwner {
        require(editions.length == items.length, "Length mismatch");
        
        uint256[] memory tokenIds = new uint256[](editions.length);
        uint256[] memory amounts = new uint256[](editions.length);
        
        for (uint256 i = 0; i < editions.length; i++) {
            tokenIds[i] = encodeTokenId(editions[i], items[i]);
            amounts[i] = 1;
            string memory tokenURI = _generateTokenURI(tokenIds[i]);
            _tokenURIs[tokenIds[i]] = tokenURI;
            emit TokenURISet(tokenIds[i], tokenURI);
        }
        
        _mintBatch(to, tokenIds, amounts, "");
        emit BookBatchMinted(to, editions, items);
    }

    /**
     * @dev Returns the base URI
     */
    function baseURI() public view returns (string memory) {
        return _baseURI;
    }
}
