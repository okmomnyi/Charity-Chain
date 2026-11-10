// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {HashLib} from "../contracts/libraries/HashLib.sol";
import {IDonationLedger} from "../contracts/interfaces/IDonationLedger.sol";

/// @notice Loads the shared golden vectors (produced by the JS side in
///         `scripts/gen-vectors.mjs`) and asserts the Solidity HashLib produces the
///         exact same record hash. This is the cross-implementation pin: if Solidity
///         and TypeScript ever diverge on hashing, this test fails.
contract VectorsTest is Test {
    using stdJson for string;

    string internal json;

    function setUp() public {
        json = vm.readFile("shared/vectors/donations.json");
    }

    function test_TypehashMatches() public view {
        bytes32 tsTypehash = json.readBytes32(".typehash");
        assertEq(tsTypehash, HashLib.DONATION_TYPEHASH, "typehash drift between TS and Solidity");
    }

    function test_DonationHashesMatch() public view {
        // Two vectors are defined; assert each.
        _check(0);
        _check(1);
    }

    function _check(uint256 i) internal view {
        string memory p = string.concat(".donations[", vm.toString(i), "]");
        bytes32 donationId = json.readBytes32(string.concat(p, ".donationId"));
        IDonationLedger.Donation memory d = IDonationLedger.Donation({
            donorRef: json.readBytes32(string.concat(p, ".donorRef")),
            amountMinor: uint64(vm.parseUint(json.readString(string.concat(p, ".amountMinor")))),
            currency: json.readBytes32(string.concat(p, ".currency")),
            receivedAt: uint64(vm.parseUint(json.readString(string.concat(p, ".receivedAt")))),
            metadataHash: json.readBytes32(string.concat(p, ".metadataHash")),
            correctsId: json.readBytes32(string.concat(p, ".correctsId"))
        });
        bytes32 expected = json.readBytes32(string.concat(p, ".recordHash"));
        assertEq(HashLib.hashDonation(donationId, d), expected, "hash mismatch with golden vector");
    }
}
