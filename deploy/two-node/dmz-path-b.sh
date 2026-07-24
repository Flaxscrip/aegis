#!/usr/bin/env bash
#
# dmz-path-b.sh — the full cross-node DMZ assertion (Hearthold B6, "verification without republication").
#
# A COUNTERPARTY (warden@nodeA) mints a credential. The SUBJECT verifies it inside a peerless DMZ
# (DmzSession from @hearthold/core, pointed at deploy/topology/docker-compose.dmz.yml) — then we assert
# the subject's OWN node (node B) never received the ops. Verified without republication.
#
# Prereq: DMZ up (docker compose -p aegis-dmz -f deploy/topology/docker-compose.dmz.yml up -d),
#         data-hh-issuer wallet provisioned (harness-hearthold-delivery.sh), host has node 22+ + ~/hearthold built.
set -uo pipefail
cd "$(dirname "$0")/../.."
HH="$PWD"; PP="${HEARTHOLD_PP:-aegis-hh}"; DMZ_URL="http://127.0.0.1:4260"; HEARTHOLD_SRC="${HEARTHOLD_SRC:-/Users/flaxscrip/hearthold}"
WARDEN=$(cat /tmp/hh-issuer.did 2>/dev/null)
PASS=0; FAIL=0
assert(){ if [ "$2" -eq 0 ]; then echo "  PASS  $1"; PASS=$((PASS+1)); else echo "  FAIL  $1"; FAIL=$((FAIL+1)); fi; }

echo "== PRE: the DMZ target is peerless (registries=[local]) =="
curl -s -m4 "$DMZ_URL/api/v1/registries" 2>/dev/null | grep -q '^\["local"\]$'; assert "DMZ passes assertPeerlessTarget (registries=[local])" $?

echo "== COUNTERPARTY (warden@nodeA) mints a credential on ITS node =="
J=$(docker run --rm --network archon_default -v "$HH/data-hh-issuer:/data" -v "$HH/deploy/two-node/hh:/app/hh" \
  -e HEARTHOLD_NODE_URL=http://drawbridge:4222 -e HEARTHOLD_REGISTRY=local -e HEARTHOLD_DATA_ROOT=/data -e HEARTHOLD_PASSPHRASE=$PP \
  --entrypoint node hearthold:sandbox hh/issue-pathb.mjs "$WARDEN" 2>/dev/null | tail -1)
CRED=$(echo "$J"   | python3 -c 'import sys,json;print(json.load(sys.stdin).get("credDid",""))' 2>/dev/null)
SCHEMA=$(echo "$J" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("schemaDid",""))' 2>/dev/null)
ISSUER=$(echo "$J" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("issuerDid",""))' 2>/dev/null)
[ -n "$CRED" ] && [ -n "$SCHEMA" ] && [ -n "$ISSUER" ]; assert "counterparty issued a credential ($CRED)" $?

echo "== export the counterparty's op chains from node A =="
docker exec aegis-cli-1 node scripts/admin-cli.js export-did "$ISSUER" > /tmp/pb-issuer.json 2>/dev/null
docker exec aegis-cli-1 node scripts/admin-cli.js export-did "$SCHEMA" > /tmp/pb-schema.json 2>/dev/null
docker exec aegis-cli-1 node scripts/admin-cli.js export-did "$CRED"   > /tmp/pb-vc.json 2>/dev/null
python3 -c 'import json;[json.load(open(f)) for f in ["/tmp/pb-issuer.json","/tmp/pb-schema.json","/tmp/pb-vc.json"]]' 2>/dev/null; assert "op chains exported (issuer, schema, credential)" $?

echo "== SUBJECT verifies the counterparty credential INSIDE the DMZ (never its own node) =="
rm -rf /tmp/pb-wallet; mkdir -p /tmp/pb-wallet
# ESM resolves @hearthold/core from the SCRIPT's tree, so run the glue from inside ~/hearthold.
cp "$HH/deploy/two-node/hh/path-b-dmz.mjs" "$HEARTHOLD_SRC/.path-b-dmz.mjs"
OUT=$(cd "$HEARTHOLD_SRC" && ISSUER_OPS=/tmp/pb-issuer.json SCHEMA_OPS=/tmp/pb-schema.json VC_OPS=/tmp/pb-vc.json \
  ISSUER_DID="$ISSUER" SCHEMA_DID="$SCHEMA" VC_DID="$CRED" \
  HEARTHOLD_NODE_URL="$DMZ_URL" HEARTHOLD_DMZ_URL="$DMZ_URL" HEARTHOLD_REGISTRY=local \
  HEARTHOLD_DATA_ROOT=/tmp/pb-wallet HEARTHOLD_PASSPHRASE=$PP \
  timeout 90 node --experimental-strip-types "$HEARTHOLD_SRC/.path-b-dmz.mjs" 2>&1)
rm -f "$HEARTHOLD_SRC/.path-b-dmz.mjs"
echo "$OUT" | sed 's/^/    /'
echo "$OUT" | grep -q 'RESULT VERIFIED_IN_DMZ'; assert "counterparty credential VERIFIED in the DMZ" $?

echo "== THE ASSERTION — the subject's OWN node (node B) never held the ops =="
# node B has a fallback to node A, so we must check its LOCAL db (--local), not a fallback-resolvable view.
LOCAL=$(docker exec aegisb-cli-b-1 node scripts/archon-cli.js resolve-did "$CRED" --local 2>&1)
echo "$LOCAL" | grep -qiE 'not found|notFound|unknown|error|no such'; assert "node B LOCAL db does NOT hold the VC (verification did not republish)" $?
# sanity: the counterparty (node A) DOES hold it locally
docker exec aegis-cli-1 node scripts/archon-cli.js resolve-did "$CRED" 2>/dev/null | grep -q "$CRED"; assert "counterparty node A DOES hold it (sanity)" $?
# ephemeral proof, Aegis-owned half: session.teardown() cleared the session; now destroy the INSTANCE.
docker compose -p aegis-dmz -f deploy/topology/docker-compose.dmz.yml down -v >/dev/null 2>&1
docker compose -p aegis-dmz -f deploy/topology/docker-compose.dmz.yml up -d >/dev/null 2>&1
for i in $(seq 1 8); do [ "$(curl -s -m3 $DMZ_URL/api/v1/ready 2>/dev/null)" = "true" ] && break; sleep 3; done
curl -s -m4 "$DMZ_URL/api/v1/did/$CRED" 2>/dev/null | grep -qiE 'notFound|invalidDid'; assert "ephemeral DMZ instance destroyed (down -v) -> imported ops gone; fresh instance empty" $?

echo "== RESULT: $PASS passed, $FAIL failed =="
rm -f /tmp/pb-issuer.json /tmp/pb-schema.json /tmp/pb-vc.json
[ "$FAIL" -eq 0 ]
