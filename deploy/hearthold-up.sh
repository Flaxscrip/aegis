#!/usr/bin/env bash
# Bring the Hearthold agent stack up/down on an isolated Aegis node — SAFELY.
#
# Answers Hearthold ask #2 (HEARTHOLD-ASK-network-defaults.md): docker-compose.hearthold.yml no longer
# hardcodes a network — it now REQUIRES `HEARTHOLD_DOCKER_NETWORK` and fails loud without it, so no bring-up
# silently joins the generic egress-capable `archon_default` a stock Archon compose would create.
#
# This wrapper does two things:
#   1. Names the network deliberately (defaults to `archon_default`, which on an Aegis node is internal:true).
#   2. ENFORCES the invariant the ask exists to protect — it refuses to start unless that network is actually
#      `internal:true`. A Hearthold node never joins an egress-capable network. (The L6 fail-loud guard.)
#
#   deploy/hearthold-up.sh                 # up on archon_default (must be internal:true)
#   HEARTHOLD_DOCKER_NETWORK=aegisb_default deploy/hearthold-up.sh
#   deploy/hearthold-up.sh down
#   deploy/hearthold-up.sh ps              # any other compose subcommand passes through
set -euo pipefail

NET="${HEARTHOLD_DOCKER_NETWORK:-archon_default}"
HH="${HEARTHOLD_REPO:-$HOME/hearthold}"
CMD="${1:-up}"

[ -f "$HH/docker-compose.hearthold.yml" ] || {
  echo "ERROR: no docker-compose.hearthold.yml under $HH (set HEARTHOLD_REPO to the hearthold repo)." >&2; exit 1; }

# --- L6 guard: only ever join an ISOLATED network ---
if ! docker network inspect "$NET" >/dev/null 2>&1; then
  echo "ERROR: docker network '$NET' does not exist. Create the isolated node network first" >&2
  echo "       (e.g. bring up the node core, or: docker network create --internal $NET)." >&2
  exit 1
fi
INTERNAL=$(docker network inspect "$NET" --format '{{.Internal}}' 2>/dev/null)
if [ "$INTERNAL" != "true" ]; then
  echo "REFUSING: network '$NET' is internal=$INTERNAL (egress-capable)." >&2
  echo "  A Hearthold node must join an ISOLATED (internal:true) network. Point HEARTHOLD_DOCKER_NETWORK at" >&2
  echo "  an internal network, or make '$NET' internal. (This is the invariant Hearthold ask #2 protects.)" >&2
  exit 1
fi

export HEARTHOLD_DOCKER_NETWORK="$NET"
echo "Hearthold → network '$NET' (internal:true ✓)"

case "$CMD" in
  up)   ( cd "$HH" && docker compose -f docker-compose.hearthold.yml up -d "${@:2}" ) ;;
  down) ( cd "$HH" && docker compose -f docker-compose.hearthold.yml down "${@:2}" ) ;;
  *)    ( cd "$HH" && docker compose -f docker-compose.hearthold.yml "$@" ) ;;
esac
