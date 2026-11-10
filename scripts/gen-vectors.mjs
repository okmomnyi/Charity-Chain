// Generates the shared golden hashing vectors from the JS/TS side (ethers), so the
// Solidity test can assert HashLib produces byte-identical hashes. This stands in for
// `shared/hashing/hashDonation` in the TypeScript codebase.
//
// Run:  node scripts/gen-vectors.mjs   (requires `ethers` installed)
// Writes: shared/vectors/donations.json
import { AbiCoder, keccak256, toUtf8Bytes } from "ethers";
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const coder = AbiCoder.defaultAbiCoder();

const DONATION_TYPEHASH = keccak256(
  toUtf8Bytes(
    "Donation(bytes32 donationId,bytes32 donorRef,uint64 amountMinor,bytes32 currency,uint64 receivedAt,bytes32 metadataHash,bytes32 correctsId)"
  )
);

function hashDonation(d) {
  return keccak256(
    coder.encode(
      ["bytes32", "bytes32", "bytes32", "uint64", "bytes32", "uint64", "bytes32", "bytes32"],
      [
        DONATION_TYPEHASH,
        d.donationId,
        d.donorRef,
        d.amountMinor,
        d.currency,
        d.receivedAt,
        d.metadataHash,
        d.correctsId,
      ]
    )
  );
}

// Fields are explicit bytes32 hex so Solidity and JS use identical inputs.
const cases = [
  {
    name: "basic-usd",
    donationId: "0x0000000000000000000000000000000000000000000000000000000000000001",
    donorRef: "0x0000000000000000000000000000000000000000000000000000000000000002",
    amountMinor: 1,
    currency: "0x5553440000000000000000000000000000000000000000000000000000000000", // "USD"
    receivedAt: 2,
    metadataHash: "0x0000000000000000000000000000000000000000000000000000000000000003",
    correctsId: "0x0000000000000000000000000000000000000000000000000000000000000000",
  },
  {
    name: "large-eur-correction",
    donationId: "0xabced00000000000000000000000000000000000000000000000000000000001",
    donorRef: "0x1111111111111111111111111111111111111111111111111111111111111111",
    amountMinor: "18446744073709551615", // uint64 max
    currency: "0x4555520000000000000000000000000000000000000000000000000000000000", // "EUR"
    receivedAt: "1700000000",
    metadataHash: "0x2222222222222222222222222222222222222222222222222222222222222222",
    correctsId: "0xabced00000000000000000000000000000000000000000000000000000000000",
  },
];

const vectors = cases.map((c) => ({
  ...c,
  // numeric fields as strings for unambiguous parsing on the Solidity side
  amountMinor: String(c.amountMinor),
  receivedAt: String(c.receivedAt),
  recordHash: hashDonation(c),
}));
const out = { typehash: DONATION_TYPEHASH, donations: vectors };

const here = dirname(fileURLToPath(import.meta.url));
const dest = resolve(here, "..", "shared", "vectors", "donations.json");
mkdirSync(dirname(dest), { recursive: true });
writeFileSync(dest, JSON.stringify(out, null, 2) + "\n");
console.log("wrote", dest);
for (const v of vectors) console.log(v.name, v.recordHash);
