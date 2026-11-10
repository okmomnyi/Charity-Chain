#!/usr/bin/env bash
# Spin up a local notary chain for development:
#   1. start Anvil (chain 31337)
#   2. deploy all contracts + wire roles + bootstrap signatories
#   3. write shared/deployments/local.json
# The relayer and three signatories use Anvil's pre-funded default accounts, so no
# extra funding step is needed. Stop with Ctrl-C.
#
# Requires: forge, anvil, node on PATH.  Run from the blockchain/ directory.
set -euo pipefail

RPC="http://127.0.0.1:8545"

# Anvil default accounts (deterministic mnemonic). These are PUBLIC test keys — dev only.
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 # acct 0
export ADMIN_ADDRESS=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266                      # acct 0
export RELAYER_ADDRESS=0x70997970C51812dc3A010C7d01b50e0d17dc79C8                    # acct 1
export ORACLE_ADDRESS=0x70997970C51812dc3A010C7d01b50e0d17dc79C8                     # acct 1
export SIGNATORY_1=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC                        # acct 2
export SIGNATORY_2=0x90F79bf6EB2c4f870365E785982E1f101E93b906                        # acct 3
export SIGNATORY_3=0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65                        # acct 4

cleanup() { [[ -n "${ANVIL_PID:-}" ]] && kill "$ANVIL_PID" 2>/dev/null || true; }
trap cleanup EXIT

echo "▶ starting anvil..."
anvil --silent &
ANVIL_PID=$!

# wait for the RPC to answer
for i in $(seq 1 30); do
  if cast block-number --rpc-url "$RPC" >/dev/null 2>&1; then break; fi
  sleep 0.3
done

echo "▶ deploying..."
forge script scripts/Deploy.s.sol:Deploy --rpc-url "$RPC" --broadcast -vv

echo "▶ writing manifest..."
node scripts/write-manifest.mjs local 31337

echo "✓ local chain ready at $RPC (anvil pid $ANVIL_PID). Ctrl-C to stop."
wait "$ANVIL_PID"

