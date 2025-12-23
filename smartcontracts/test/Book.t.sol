// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Book} from "../src/book.sol";

/**
 * @title BookTest
 * @dev Comprehensive test suite for the Book ERC-1155 contract
 * @notice Tests follow Foundry best practices with proper setup, assertions, and edge cases
 */
contract BookTest is Test {
    Book public book;

    // Test addresses
    address public owner;
    address public alice;
    address public bob;

    // Constants
    string public constant BASE_URI = "https://jeffprestes.github.io/bookerc1155/metadata/";
    uint256 public constant EDITION_MULTIPLIER = 1_000_000;

    // Events (must match contract events for expectEmit)
    event BookMinted(address indexed to, uint256 indexed edition, uint256 indexed item);
    event BookBatchMinted(address indexed to, uint256[] editions, uint256[] items);
    event TokenURISet(uint256 indexed tokenId, string uri);
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);
    event TransferBatch(address indexed operator, address indexed from, address indexed to, uint256[] ids, uint256[] values);

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        vm.prank(owner);
        book = new Book(owner, BASE_URI);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_DeploymentSetsOwner() public view {
        assertEq(book.owner(), owner);
    }

    function test_DeploymentSetsBaseURI() public view {
        assertEq(book.baseURI(), BASE_URI);
    }

    function test_DeploymentSetsEditionMultiplier() public view {
        assertEq(book.EDITION_MULTIPLIER(), EDITION_MULTIPLIER);
    }

    /*//////////////////////////////////////////////////////////////
                        TOKEN ID ENCODING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_EncodeTokenId() public view {
        // Edition 1, Item 1 => 1_000_001
        assertEq(book.encodeTokenId(1, 1), 1_000_001);

        // Edition 1, Item 999_999 => 1_999_999
        assertEq(book.encodeTokenId(1, 999_999), 1_999_999);

        // Edition 0, Item 1 => 1
        assertEq(book.encodeTokenId(0, 1), 1);

        // Edition 100, Item 50 => 100_000_050
        assertEq(book.encodeTokenId(100, 50), 100_000_050);
    }

    function test_DecodeTokenId() public view {
        // Decode 1_000_001 => Edition 1, Item 1
        (uint256 edition, uint256 item) = book.decodeTokenId(1_000_001);
        assertEq(edition, 1);
        assertEq(item, 1);

        // Decode 1_999_999 => Edition 1, Item 999_999
        (edition, item) = book.decodeTokenId(1_999_999);
        assertEq(edition, 1);
        assertEq(item, 999_999);

        // Decode 100_000_050 => Edition 100, Item 50
        (edition, item) = book.decodeTokenId(100_000_050);
        assertEq(edition, 100);
        assertEq(item, 50);
    }

    function test_EncodeDecodeRoundTrip() public view {
        uint256 edition = 42;
        uint256 item = 12345;

        uint256 tokenId = book.encodeTokenId(edition, item);
        (uint256 decodedEdition, uint256 decodedItem) = book.decodeTokenId(tokenId);

        assertEq(decodedEdition, edition);
        assertEq(decodedItem, item);
    }

    function testFuzz_EncodeDecodeRoundTrip(uint256 edition, uint256 item) public view {
        // Bound item to valid range (0 to 999_999)
        item = bound(item, 0, EDITION_MULTIPLIER - 1);
        // Bound edition to reasonable range to avoid overflow when multiplied
        // Max safe edition: (type(uint256).max - item) / EDITION_MULTIPLIER
        edition = bound(edition, 0, 1_000_000_000); // 1 billion editions is more than enough

        uint256 tokenId = book.encodeTokenId(edition, item);
        (uint256 decodedEdition, uint256 decodedItem) = book.decodeTokenId(tokenId);

        assertEq(decodedEdition, edition);
        assertEq(decodedItem, item);
    }

    function test_RevertWhen_ItemTooLarge() public {
        vm.expectRevert("Item number too large");
        book.encodeTokenId(1, EDITION_MULTIPLIER);
    }

    function test_RevertWhen_ItemExceedsMultiplier() public {
        vm.expectRevert("Item number too large");
        book.encodeTokenId(1, EDITION_MULTIPLIER + 1);
    }

    /*//////////////////////////////////////////////////////////////
                            MINT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MintSingleBook() public {
        uint256 edition = 1;
        uint256 item = 1;
        uint256 expectedTokenId = book.encodeTokenId(edition, item);

        vm.prank(owner);
        book.mint(alice, edition, item);

        assertEq(book.balanceOf(alice, expectedTokenId), 1);
    }

    function test_MintEmitsEvents() public {
        uint256 edition = 1;
        uint256 item = 1;
        uint256 expectedTokenId = book.encodeTokenId(edition, item);
        string memory expectedURI = string(abi.encodePacked(BASE_URI, "1000001.json"));

        vm.expectEmit(true, true, false, true);
        emit TokenURISet(expectedTokenId, expectedURI);

        vm.expectEmit(true, true, true, true);
        emit BookMinted(alice, edition, item);

        vm.prank(owner);
        book.mint(alice, edition, item);
    }

    function test_MintSetsTokenURI() public {
        uint256 edition = 1;
        uint256 item = 1;
        uint256 expectedTokenId = book.encodeTokenId(edition, item);

        vm.prank(owner);
        book.mint(alice, edition, item);

        string memory expectedURI = string(abi.encodePacked(BASE_URI, "1000001.json"));
        assertEq(book.uri(expectedTokenId), expectedURI);
    }

    function test_RevertWhen_NonOwnerMints() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        book.mint(alice, 1, 1);
    }

    function testFuzz_Mint(address to, uint256 edition, uint256 item) public {
        vm.assume(to != address(0));
        item = bound(item, 0, EDITION_MULTIPLIER - 1);
        // Bound edition to reasonable range to avoid overflow
        edition = bound(edition, 0, 1_000_000_000); // 1 billion editions is more than enough

        uint256 expectedTokenId = book.encodeTokenId(edition, item);

        vm.prank(owner);
        book.mint(to, edition, item);

        assertEq(book.balanceOf(to, expectedTokenId), 1);
    }

    /*//////////////////////////////////////////////////////////////
                        MINT BATCH TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MintBatch() public {
        uint256[] memory editions = new uint256[](3);
        uint256[] memory items = new uint256[](3);

        editions[0] = 1;
        items[0] = 1;
        editions[1] = 1;
        items[1] = 2;
        editions[2] = 2;
        items[2] = 1;

        vm.prank(owner);
        book.mintBatch(alice, editions, items);

        assertEq(book.balanceOf(alice, book.encodeTokenId(1, 1)), 1);
        assertEq(book.balanceOf(alice, book.encodeTokenId(1, 2)), 1);
        assertEq(book.balanceOf(alice, book.encodeTokenId(2, 1)), 1);
    }

    function test_MintBatchEmitsEvents() public {
        uint256[] memory editions = new uint256[](2);
        uint256[] memory items = new uint256[](2);

        editions[0] = 1;
        items[0] = 1;
        editions[1] = 1;
        items[1] = 2;

        vm.expectEmit(true, false, false, true);
        emit BookBatchMinted(alice, editions, items);

        vm.prank(owner);
        book.mintBatch(alice, editions, items);
    }

    function test_MintBatchSetsTokenURIs() public {
        uint256[] memory editions = new uint256[](2);
        uint256[] memory items = new uint256[](2);

        editions[0] = 1;
        items[0] = 1;
        editions[1] = 2;
        items[1] = 5;

        vm.prank(owner);
        book.mintBatch(alice, editions, items);

        string memory expectedURI1 = string(abi.encodePacked(BASE_URI, "1000001.json"));
        string memory expectedURI2 = string(abi.encodePacked(BASE_URI, "2000005.json"));

        assertEq(book.uri(book.encodeTokenId(1, 1)), expectedURI1);
        assertEq(book.uri(book.encodeTokenId(2, 5)), expectedURI2);
    }

    function test_RevertWhen_MintBatchLengthMismatch() public {
        uint256[] memory editions = new uint256[](2);
        uint256[] memory items = new uint256[](3);

        editions[0] = 1;
        editions[1] = 2;
        items[0] = 1;
        items[1] = 2;
        items[2] = 3;

        vm.prank(owner);
        vm.expectRevert("Length mismatch");
        book.mintBatch(alice, editions, items);
    }

    function test_RevertWhen_NonOwnerMintsBatch() public {
        uint256[] memory editions = new uint256[](1);
        uint256[] memory items = new uint256[](1);
        editions[0] = 1;
        items[0] = 1;

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        book.mintBatch(alice, editions, items);
    }

    /*//////////////////////////////////////////////////////////////
                            URI TESTS
    //////////////////////////////////////////////////////////////*/

    function test_UriReturnsCorrectFormat() public {
        uint256 tokenId = 1_000_001;

        vm.prank(owner);
        book.mint(alice, 1, 1);

        string memory expectedURI = string(abi.encodePacked(BASE_URI, "1000001.json"));
        assertEq(book.uri(tokenId), expectedURI);
    }

    function test_BookUriReturnsCorrectFormat() public {
        vm.prank(owner);
        book.mint(alice, 1, 1);

        string memory expectedURI = string(abi.encodePacked(BASE_URI, "1000001.json"));
        assertEq(book.bookURI(1, 1), expectedURI);
    }

    function test_SetBaseURI() public {
        string memory newBaseURI = "https://example.com/metadata/";

        vm.prank(owner);
        book.setBaseURI(newBaseURI);

        assertEq(book.baseURI(), newBaseURI);
    }

    function test_RevertWhen_NonOwnerSetsBaseURI() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        book.setBaseURI("https://malicious.com/");
    }

    function test_SetCustomTokenURI() public {
        uint256 tokenId = 1_000_001;
        string memory customURI = "ipfs://QmCustomHash/metadata.json";

        vm.prank(owner);
        book.mint(alice, 1, 1);

        vm.prank(owner);
        book.setTokenURI(tokenId, customURI);

        assertEq(book.uri(tokenId), customURI);
    }

    function test_SetCustomTokenURIWithEditionItem() public {
        string memory customURI = "ipfs://QmCustomHash/metadata.json";

        vm.prank(owner);
        book.mint(alice, 1, 1);

        vm.prank(owner);
        book.setTokenURI(1, 1, customURI);

        assertEq(book.uri(book.encodeTokenId(1, 1)), customURI);
        assertEq(book.bookURI(1, 1), customURI);
    }

    function test_SetTokenURIEmitsEvent() public {
        uint256 tokenId = 1_000_001;
        string memory customURI = "ipfs://QmCustomHash/metadata.json";

        vm.prank(owner);
        book.mint(alice, 1, 1);

        vm.expectEmit(true, false, false, true);
        emit TokenURISet(tokenId, customURI);

        vm.prank(owner);
        book.setTokenURI(tokenId, customURI);
    }

    function test_RevertWhen_NonOwnerSetsTokenURI() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        book.setTokenURI(1_000_001, "https://malicious.com/");
    }

    function test_CustomURIOverridesDefault() public {
        uint256 tokenId = 1_000_001;
        string memory customURI = "ipfs://QmCustom/special.json";

        vm.prank(owner);
        book.mint(alice, 1, 1);

        // Before custom URI is set, should return default
        string memory defaultURI = string(abi.encodePacked(BASE_URI, "1000001.json"));
        assertEq(book.uri(tokenId), defaultURI);

        // After setting custom URI
        vm.prank(owner);
        book.setTokenURI(tokenId, customURI);
        assertEq(book.uri(tokenId), customURI);
    }

    /*//////////////////////////////////////////////////////////////
                        ERC-1155 TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SafeTransferFrom() public {
        uint256 tokenId = book.encodeTokenId(1, 1);

        vm.prank(owner);
        book.mint(alice, 1, 1);

        vm.prank(alice);
        book.safeTransferFrom(alice, bob, tokenId, 1, "");

        assertEq(book.balanceOf(alice, tokenId), 0);
        assertEq(book.balanceOf(bob, tokenId), 1);
    }

    function test_SafeBatchTransferFrom() public {
        uint256[] memory editions = new uint256[](2);
        uint256[] memory items = new uint256[](2);
        editions[0] = 1;
        items[0] = 1;
        editions[1] = 1;
        items[1] = 2;

        vm.prank(owner);
        book.mintBatch(alice, editions, items);

        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = book.encodeTokenId(1, 1);
        ids[1] = book.encodeTokenId(1, 2);
        amounts[0] = 1;
        amounts[1] = 1;

        vm.prank(alice);
        book.safeBatchTransferFrom(alice, bob, ids, amounts, "");

        assertEq(book.balanceOf(alice, ids[0]), 0);
        assertEq(book.balanceOf(alice, ids[1]), 0);
        assertEq(book.balanceOf(bob, ids[0]), 1);
        assertEq(book.balanceOf(bob, ids[1]), 1);
    }

    function test_SetApprovalForAll() public {
        uint256 tokenId = book.encodeTokenId(1, 1);

        vm.prank(owner);
        book.mint(alice, 1, 1);

        vm.prank(alice);
        book.setApprovalForAll(bob, true);

        assertTrue(book.isApprovedForAll(alice, bob));

        // Bob can now transfer Alice's tokens
        vm.prank(bob);
        book.safeTransferFrom(alice, bob, tokenId, 1, "");

        assertEq(book.balanceOf(bob, tokenId), 1);
    }

    /*//////////////////////////////////////////////////////////////
                        OWNERSHIP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_TransferOwnership() public {
        vm.prank(owner);
        book.transferOwnership(alice);

        assertEq(book.owner(), alice);
    }

    function test_NewOwnerCanMint() public {
        vm.prank(owner);
        book.transferOwnership(alice);

        vm.prank(alice);
        book.mint(bob, 1, 1);

        assertEq(book.balanceOf(bob, book.encodeTokenId(1, 1)), 1);
    }

    function test_OldOwnerCannotMintAfterTransfer() public {
        vm.prank(owner);
        book.transferOwnership(alice);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", owner));
        book.mint(bob, 1, 1);
    }

    function test_RenounceOwnership() public {
        vm.prank(owner);
        book.renounceOwnership();

        assertEq(book.owner(), address(0));
    }

    function test_RevertWhen_MintAfterRenounceOwnership() public {
        vm.prank(owner);
        book.renounceOwnership();

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", owner));
        book.mint(alice, 1, 1);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MintToZeroEdition() public {
        vm.prank(owner);
        book.mint(alice, 0, 1);

        assertEq(book.balanceOf(alice, book.encodeTokenId(0, 1)), 1);
    }

    function test_MintToZeroItem() public {
        vm.prank(owner);
        book.mint(alice, 1, 0);

        uint256 tokenId = book.encodeTokenId(1, 0);
        assertEq(tokenId, 1_000_000);
        assertEq(book.balanceOf(alice, tokenId), 1);
    }

    function test_MintMaxValidItem() public {
        uint256 maxItem = EDITION_MULTIPLIER - 1; // 999_999

        vm.prank(owner);
        book.mint(alice, 1, maxItem);

        uint256 expectedTokenId = book.encodeTokenId(1, maxItem);
        assertEq(book.balanceOf(alice, expectedTokenId), 1);
    }

    function test_BalanceOfBatch() public {
        uint256[] memory editions = new uint256[](3);
        uint256[] memory items = new uint256[](3);
        editions[0] = 1;
        items[0] = 1;
        editions[1] = 1;
        items[1] = 2;
        editions[2] = 2;
        items[2] = 1;

        vm.prank(owner);
        book.mintBatch(alice, editions, items);

        address[] memory accounts = new address[](3);
        accounts[0] = alice;
        accounts[1] = alice;
        accounts[2] = alice;

        uint256[] memory ids = new uint256[](3);
        ids[0] = book.encodeTokenId(1, 1);
        ids[1] = book.encodeTokenId(1, 2);
        ids[2] = book.encodeTokenId(2, 1);

        uint256[] memory balances = book.balanceOfBatch(accounts, ids);

        assertEq(balances[0], 1);
        assertEq(balances[1], 1);
        assertEq(balances[2], 1);
    }

    function test_UnmintedTokenReturnsDefaultURI() public view {
        // Token that was never minted should still return a URI based on baseURI
        uint256 tokenId = 999_000_999;
        string memory expectedURI = string(abi.encodePacked(BASE_URI, "999000999.json"));
        assertEq(book.uri(tokenId), expectedURI);
    }

    function test_SupportsInterface() public view {
        // ERC-1155 interface ID
        bytes4 erc1155InterfaceId = 0xd9b67a26;
        assertTrue(book.supportsInterface(erc1155InterfaceId));

        // ERC-1155 Metadata URI interface ID
        bytes4 erc1155MetadataURIInterfaceId = 0x0e89341c;
        assertTrue(book.supportsInterface(erc1155MetadataURIInterfaceId));

        // ERC-165 interface ID
        bytes4 erc165InterfaceId = 0x01ffc9a7;
        assertTrue(book.supportsInterface(erc165InterfaceId));
    }
}
