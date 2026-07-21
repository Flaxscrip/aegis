#!/usr/bin/env bash
#
# AEGIS demo extension — a 3rd-party BANK issues a Balance Statement VC into the Sovereign's private KB.
#
# This lives in the AEGIS repo and does NOT modify Hearthold: it docker-cp's the accompanying
# e2e-finance-balance-vc.ts into the running hearthold-warden container and runs it there against the
# isolated node, in a throwaway data root. The script uses only Hearthold's public @hearthold/core +
# @hearthold/warden APIs (the VC->KB bridge), and stands up a distinct bank issuer via its own data root
# (no new Hearthold agent role).
#
# Prereq: the Hearthold sandbox is up (docker compose -f ~/hearthold/docker-compose.hearthold.yml up -d)
# and the Archon node is running (the isolated stack).
#
#   ./run-balance-vc.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CONTAINER=hearthold-warden
SCRIPT=e2e-finance-balance-vc.ts
ROOT=/data/flow-aegis-balance-vc

command -v docker >/dev/null || { echo "docker not found"; exit 1; }
docker ps --format '{{.Names}}' | grep -qx "$CONTAINER" || { echo "container $CONTAINER not running — bring the Hearthold sandbox up first"; exit 1; }

printf '\n\033[1;36m━━ finance-balance-vc — a bank issues a Balance Statement VC → the Sovereign\xE2\x80\x99s private KB ━━\033[0m\n'
printf '   \033[2mInjected into %s at runtime (Hearthold repo untouched); throwaway data root.\033[0m\n' "$CONTAINER"

docker cp "$HERE/$SCRIPT" "$CONTAINER:/app/scripts/$SCRIPT"
docker exec "$CONTAINER" sh -c "rm -rf $ROOT 2>/dev/null" || true
docker compose -f "${HEARTHOLD_DIR:-$HOME/hearthold}/docker-compose.hearthold.yml" exec -T \
  -e HEARTHOLD_DATA_ROOT="$ROOT" \
  -e HEARTHOLD_CLASSIFIER=quarantine -e HEARTHOLD_INDEX=off \
  -e HEARTHOLD_PASSPHRASE=aegis-finance-balance-vc \
  warden node --experimental-strip-types "scripts/$SCRIPT" 2>&1 | grep -vE 'ExperimentalWarning|trace-warning'
# leave no trace of the injected script in the container image layer's view
docker exec "$CONTAINER" sh -c "rm -f /app/scripts/$SCRIPT" || true

printf '\n\033[32m✓ 3rd-party bank Balance Statement VC → private KB partition — verified in the isolated sandbox\033[0m\n'
