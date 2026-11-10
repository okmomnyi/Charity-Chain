// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { HashLib } from "../../contracts/libraries/HashLib.sol";
contract HashLibHarness {
    function getId(
        string memory kind,
        string memory uuid
    ) external pure returns (bytes32) {
        return HashLib.idOf(kind, uuid);
    }
}
contract HashLibTest is Test {
    function test_IdOfDonationGoldenVector() public pure {
        bytes32 result = HashLib.idOf("donation", "d1a2b3c4-0000-0000-0000-000000000001");

        assert(result == 0xc6c7eae886c7a49306015a5d23f82efc9b95323141a50401017019e5bbd7b734);
    }

    // Donation hashing is pinned to the TS golden vectors in Vectors.t.sol
    // (shared/vectors/donations.json) and exercised in DonationLedger.t.sol.

    function test_EmptyDayRootGoldenVector() public pure {
        bytes32 result = HashLib.emptyDayRoot(20261102);

        assert(result == 0xb01bb4f26f21a81c20b6bd9afa0a0ed4c3956c71296fdcecb950b82cb519c9bc);
    }

    function test_HashMerklePairIsOrderIndependent() public pure {
        bytes32 a = keccak256("first");
        bytes32 b = keccak256("second");

        bytes32 result1 = HashLib.hashMerklePair(a, b);
        bytes32 result2 = HashLib.hashMerklePair(b, a);

        assert(result1 == result2);
    }

    function test_HashCaseProducesHash() public pure {
        bytes32 result = HashLib.hashCase(
            keccak256("case-1"), keccak256("subgroup-1"), bytes3("FOD"), 25000, 1728894190
        );

        assert(result != bytes32(0));
    }

    function test_IdOfRejectsUppercaseUUID() public {
        HashLibHarness harness = new HashLibHarness();

        vm.expectRevert(
            abi.encodeWithSignature("Error(string)", "HashLib: UUID must use lowercase hex")
        );

        harness.getId("donation", "D1A2B3C4-0000-0000-0000-000000000001");
    }
}
