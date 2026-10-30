#!/usr/bin/env bash
# Deploys MeetupAssurance, checks the deployment really landed, then verifies the source.
#
# Usage: script/deploy.sh [--network sepolia]
# Reads SEPOLIA_RPC_URL, BENEFICIARY, TARGET_WEI, DURATION_SECONDS and DEPLOYER (the address of
# the keystore account) from .env. Optional: ETHERSCAN_API_KEY. The signer is the Foundry keystore
# named by KEYSTORE_ACCOUNT (default: deployer), created with `cast wallet import`. No private key
# is read from any file.
set -euo pipefail
cd "$(dirname "$0")/.."

set -a; [ -f .env ] && . ./.env; set +a

for v in SEPOLIA_RPC_URL BENEFICIARY TARGET_WEI DURATION_SECONDS DEPLOYER; do
  [ -n "${!v:-}" ] || { echo "error: $v is not set (add it to .env)" >&2; exit 1; }
done
ACCOUNT="${KEYSTORE_ACCOUNT:-deployer}"
CHAIN_ID=11155111

[ "$(cast chain-id --rpc-url "$SEPOLIA_RPC_URL")" = "$CHAIN_ID" ] \
  || { echo "error: RPC is not Sepolia ($CHAIN_ID)" >&2; exit 1; }

# --skip-simulation makes forge take the gas estimate from the node instead of its local EVM.
# The local estimate (~0.5M) is far below what Sepolia actually charges for this deployment
# (~3.3M), so the default flow ran out of gas on-chain and deployed nothing.
# --slow waits for each transaction before sending the next.
verify_args=(--verify --verifier sourcify)
if [ -n "${ETHERSCAN_API_KEY:-}" ]; then
  verify_args=(--verify --verifier etherscan --etherscan-api-key "$ETHERSCAN_API_KEY")
fi

forge script script/Deploy.s.sol \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --account "$ACCOUNT" --sender "$DEPLOYER" \
  --broadcast --skip-simulation --slow \
  "${verify_args[@]}"

RECORD="broadcast/Deploy.s.sol/$CHAIN_ID/run-latest.json"
ADDRESS=$(python3 -c "import json;print(json.load(open('$RECORD'))['transactions'][0]['contractAddress'])")
TX=$(python3 -c "import json;print(json.load(open('$RECORD'))['transactions'][0]['hash'])")

# A broadcast record lists the address the contract *would* have; it exists even when the
# transaction failed. Confirm against the chain before reporting success.
STATUS=$(cast receipt "$TX" status --rpc-url "$SEPOLIA_RPC_URL" || true)
CODE=$(cast code "$ADDRESS" --rpc-url "$SEPOLIA_RPC_URL")
if [[ "$STATUS" != "true" && "$STATUS" != 1* && "$STATUS" != *success* ]] || [ "$CODE" = "0x" ]; then
  echo "DEPLOY FAILED: tx $TX status='$STATUS', no code at $ADDRESS" >&2
  echo "Do not record this address. Delete $RECORD and retry." >&2
  exit 1
fi

echo
echo "Deployed MeetupAssurance at $ADDRESS"
echo "  state():    $(cast call "$ADDRESS" 'state()(uint8)' --rpc-url "$SEPOLIA_RPC_URL")  (0 = Open)"
echo "  target():   $(cast call "$ADDRESS" 'target()(uint256)' --rpc-url "$SEPOLIA_RPC_URL") wei"
echo "  deadline(): $(cast call "$ADDRESS" 'deadline()(uint256)' --rpc-url "$SEPOLIA_RPC_URL")"
echo "  https://sepolia.etherscan.io/address/$ADDRESS"
echo
echo "Next: put the address in README.md and frontend/config.js."
