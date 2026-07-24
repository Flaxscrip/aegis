#!/usr/bin/env bash
#
# harness-hearthold-delivery.sh — the PHASE-4 seam wired to Hearthold's REAL primitives.
#
# Drives cross-node credential delivery across the two ISOLATED nodes using Hearthold's
# deliver-credential.ts / serve-credential-delivery.ts (issuer=hearthold-warden@nodeA,
# subject=hearthold-sovereign@nodeB, no shared registry), all offline. Complements the
# archon-primitive harness-credential-exchange.sh.
#
# Requires (see deploy/two-node/hh/AEGIS-INTEGRATION-FINDINGS.md):
#   - hearthold:sandbox image built from ~/hearthold (has credential-delivery + processEvents fix)
#   - node-URL proxy (hh/nodeurl-proxy.mjs) — substrate glue for the import/admin-endpoint routing
#     Hearthold hasn't decoupled yet
#   - --include-issuer-ops — until Archon core's verifyOperation resolves the issuer over the peer
#
# Run from repo root:  deploy/two-node/harness-hearthold-delivery.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
HH="$PWD"; PP="${HEARTHOLD_PP:-aegis-hh}"
NODEB_ADMIN="$(grep -E '^ARCHON_ADMIN_API_KEY=' deploy/two-node/nodeb.env | cut -d= -f2-)"

PASS=0; FAIL=0
assert(){ if [ "$2" -eq 0 ]; then echo "  PASS  $1"; PASS=$((PASS+1)); else echo "  FAIL  $1"; FAIL=$((FAIL+1)); fi; }
img(){ docker run --rm "$@"; }
gk_did(){ docker run --rm --network "$2" -v "$HH/$3:/data" -v "$HH/deploy/two-node/hh:/app/hh" \
  -e HEARTHOLD_NODE_URL="$4" -e HEARTHOLD_REGISTRY=local -e HEARTHOLD_DATA_ROOT=/data -e HEARTHOLD_PASSPHRASE=$PP \
  --entrypoint node hearthold:sandbox hh/provision.mjs "$1" 2>/dev/null | grep -oE 'did:cid:[a-z0-9]+' | tail -1; }

echo "== PHASE 1: image + substrate proxy =="
docker run --rm --entrypoint sh hearthold:sandbox -c 'test -f packages/core/dist/credential-delivery.js' 2>/dev/null; assert "hearthold image has credential-delivery" $?
docker rm -f aegis-nodeb-proxy >/dev/null 2>&1
docker run -d --name aegis-nodeb-proxy --network aegis-peer -v "$HH/deploy/two-node/hh:/hh" \
  -e ADMIN_KEY="$NODEB_ADMIN" --entrypoint node hearthold:sandbox /hh/nodeurl-proxy.mjs >/dev/null 2>&1
sleep 2
docker exec aegis-nodeb-proxy node -e 'const h=require("http");const b="[]";const q=h.request({host:"127.0.0.1",port:4299,path:"/api/v1/dids/import",method:"POST",headers:{"Content-Type":"application/json","Content-Length":b.length}},r=>process.exit(r.statusCode===401||r.statusCode===404?1:0));q.on("error",()=>process.exit(1));q.write(b);q.end()' 2>/dev/null; assert "import reachable via proxy (not 401/404)" $?

echo "== PHASE 2: provision agents (warden@A, sovereign@B) + start subject serve =="
ISSUER_DID=$(gk_did warden archon_default data-hh-issuer http://drawbridge:4222)
SUBJECT_DID=$(gk_did sovereign aegis-peer data-hh-subject http://aegis-nodeb-proxy:4299)
[ -n "$ISSUER_DID" ]; assert "issuer hearthold-warden provisioned ($ISSUER_DID)" $?
[ -n "$SUBJECT_DID" ]; assert "subject hearthold-sovereign provisioned ($SUBJECT_DID)" $?
docker rm -f aegis-hh-subject >/dev/null 2>&1
docker run -d --name aegis-hh-subject --network aegis-peer \
  -v "$HH/data-hh-subject:/data" -v "$HH/deploy/two-node/hh:/app/hh" \
  -e HEARTHOLD_NODE_URL=http://aegis-nodeb-proxy:4299 -e HEARTHOLD_DIDCOMM_ENDPOINT=http://drawbridge-b:4222/didcomm \
  -e HEARTHOLD_REGISTRY=local -e HEARTHOLD_DATA_ROOT=/data -e HEARTHOLD_PASSPHRASE=$PP \
  --entrypoint node hearthold:sandbox --experimental-strip-types scripts/serve-credential-delivery.ts >/dev/null 2>&1
sleep 5
docker logs aegis-hh-subject 2>&1 | grep -q "serving credential-delivery as hearthold-sovereign"; assert "subject serve daemon up" $?

echo "== PHASE 3: cross-node resolution + issue VC =="
docker exec aegis-cli-1 node scripts/archon-cli.js resolve-did "$SUBJECT_DID" >/dev/null 2>&1; assert "node A resolves subject via peer" $?
CRED_DID=$(docker run --rm --network archon_default -v "$HH/data-hh-issuer:/data" -v "$HH/deploy/two-node/hh:/app/hh" \
  -e HEARTHOLD_NODE_URL=http://drawbridge:4222 -e HEARTHOLD_REGISTRY=local -e HEARTHOLD_DATA_ROOT=/data -e HEARTHOLD_PASSPHRASE=$PP \
  --entrypoint node hearthold:sandbox hh/issue.mjs "$SUBJECT_DID" 2>/dev/null | grep -oE 'did:cid:[a-z0-9]+' | tail -1)
[ -n "$CRED_DID" ]; assert "warden issued membership VC ($CRED_DID)" $?

echo "== PHASE 4: DELIVER over DIDComm (Hearthold deliver-credential.ts) =="
ACK=$(docker run --rm --network archon_default -v "$HH/data-hh-issuer:/data" \
  -e HEARTHOLD_NODE_URL=http://drawbridge:4222 -e HEARTHOLD_DIDCOMM_ENDPOINT=http://drawbridge:4222/didcomm \
  -e HEARTHOLD_REGISTRY=local -e HEARTHOLD_DATA_ROOT=/data -e HEARTHOLD_PASSPHRASE=$PP \
  --entrypoint node hearthold:sandbox \
  --experimental-strip-types scripts/deliver-credential.ts "$SUBJECT_DID" "$CRED_DID" --include-issuer-ops 2>/dev/null)
echo "$ACK" | grep -q '"accepted": true'; assert "delivery accepted (accepted:true)" $?

echo "== PHASE 5: subject holds VC + isolation intact =="
HELD=$(docker run --rm --network aegis-peer -v "$HH/data-hh-subject:/data" -v "$HH/deploy/two-node/hh:/app/hh" \
  -e HEARTHOLD_NODE_URL=http://aegis-nodeb-proxy:4299 -e HEARTHOLD_REGISTRY=local -e HEARTHOLD_DATA_ROOT=/data -e HEARTHOLD_PASSPHRASE=$PP \
  --entrypoint node hearthold:sandbox -e "import('@hearthold/core').then(async m=>{const c=m.loadConfig();const h=await m.openKeymaster('sovereign',c,process.env.HEARTHOLD_PASSPHRASE);await h.keymaster.setCurrentId(m.IDENTITY_NAME.sovereign);const l=await h.keymaster.listCredentials();process.stdout.write(l.includes('$CRED_DID')?'yes':'no');process.exit(0)}).catch(()=>{process.stdout.write('no');process.exit(0)})" 2>/dev/null)
[ "$HELD" = "yes" ]; assert "subject hearthold-sovereign HOLDS the delivered VC" $?
docker exec aegis-gatekeeper-1 node -e 'require("http").get({host:"1.1.1.1",port:80,timeout:4000},()=>process.exit(1)).on("error",()=>process.exit(0))' 2>/dev/null; assert "node A no public egress" $?
docker exec aegisb-gatekeeper-b-1 node -e 'require("http").get({host:"1.1.1.1",port:80,timeout:4000},()=>process.exit(1)).on("error",()=>process.exit(0))' 2>/dev/null; assert "node B no public egress" $?

echo "== RESULT: $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
