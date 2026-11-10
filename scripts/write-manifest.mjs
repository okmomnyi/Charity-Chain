// Builds `shared/deployments/<network>.json` from the Foundry broadcast log of the
// Deploy script, in the manifest format ARCHITECTURE.md 5.1 expects.
//
// Run after a broadcast:
//   node scripts/write-manifest.mjs <network> <chainId>
//   e.g. node scripts/write-manifest.mjs amoy 80002
//        node scripts/write-manifest.mjs local 31337
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const [network, chainId] = process.argv.slice(2);
if (!network || !chainId) {
  console.error("usage: node scripts/write-manifest.mjs <network> <chainId>");
  process.exit(1);
}

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "..");

const runPath = resolve(root, "broadcast", "Deploy.s.sol", chainId, "run-latest.json");
let run;
try {
  run = JSON.parse(readFileSync(runPath, "utf8"));
} catch {
  console.error(`no broadcast at ${runPath} — run the Deploy script with --broadcast first`);
  process.exit(1);
}

// Map each CREATE tx to { ContractName: address }.
const contracts = {};
for (const tx of run.transactions ?? []) {
  if (tx.transactionType === "CREATE" && tx.contractName && tx.contractAddress) {
    contracts[tx.contractName] = tx.contractAddress;
  }
}

const manifest = {
  network,
  chainId: Number(chainId),
  deployedAt: new Date().toISOString(),
  commit: run.commit ?? null,
  contracts,
};

const outDir = resolve(root, "shared", "deployments");
mkdirSync(outDir, { recursive: true });
const dest = resolve(outDir, `${network}.json`);
writeFileSync(dest, JSON.stringify(manifest, null, 2) + "\n");
console.log(`wrote ${dest}`);
console.log(contracts);
