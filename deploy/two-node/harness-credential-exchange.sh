#!/usr/bin/env bash
#
# harness-credential-exchange.sh — acceptance harness for CROSS-NODE credential
# exchange between two Hearthold agents on isolated nodes that DO NOT share a registry.
#
# This is the executable definition-of-done for HEARTHOLD-ASK-cross-node-credential-
# delivery.md. It is written in HEARTHOLD's vocabulary — an *issuer agent* delivers a
# *verifiable credential* to a *subject agent* over DIDComm — with NO "card" terminology
# and NO game framing (that's Sevenfold). It currently drives the exchange through
# Archon CLI primitives + the Aegis transport (pass-card-didcomm.sh); when Hearthold
# core grows `deliverCredential` / a credential-delivery RequestHandler, swap the DELIVER
# phase to call those and this harness should still pass unchanged.
#
# Run (both nodes up, node A in peer mode with didcomm on aegis-peer):
#   deploy/two-node/harness-credential-exchange.sh
set -uo pipefail
cd "$(dirname "$0")/../.."   # repo root

CLI_A="${AEGIS_CLI_A:-archon-cli-1}"       # issuer's node
CLI_B="${AEGIS_CLI_B:-aegisb-cli-b-1}"      # subject's node
ISSUER="${ISSUER_AGENT:-issuer-agent}"
SUBJECT="${SUBJECT_AGENT:-subject-agent}"
ISSUER_EP="${ISSUER_ENDPOINT:-http://drawbridge:4222/didcomm}"      # issuer node A endpoint on aegis-peer
SUBJECT_EP="${SUBJECT_ENDPOINT:-http://drawbridge-b:4222/didcomm}"  # subject node B endpoint on aegis-peer

clia(){ docker exec "$CLI_A" node scripts/archon-cli.js "$@"; }
clib(){ docker exec "$CLI_B" node scripts/archon-cli.js "$@"; }
PASS=0; FAIL=0
assert(){ # assert "<label>" <condition-exit-code>
  if [ "$2" -eq 0 ]; then echo "  PASS  $1"; PASS=$((PASS+1)); else echo "  FAIL  $1"; FAIL=$((FAIL+1)); fi
}
# create an agent identity if absent, verifying (use-id exits 0 even on Unknown ID)
ensure_agent(){ local cli="$1" name="$2"
  $cli list-ids 2>/dev/null | sed 's/ *<<< current//' | grep -qxF "$name" || $cli create-id "$name" >/dev/null 2>&1
  $cli list-ids 2>/dev/null | sed 's/ *<<< current//' | grep -qxF "$name"
}
did_of(){ $1 resolve-id 2>/dev/null | grep -m1 '"id": "did:cid:' | grep -oE 'did:cid:[a-z0-9]+'; }

echo "== PHASE 1: provision the two agents on separate isolated nodes =="
ensure_agent clia "$ISSUER";  assert "issuer agent '$ISSUER' exists on node A"  $?
ensure_agent clib "$SUBJECT"; assert "subject agent '$SUBJECT' exists on node B" $?
clia use-id "$ISSUER" >/dev/null; clib use-id "$SUBJECT" >/dev/null
ISSUER_DID=$(did_of clia); SUBJECT_DID=$(did_of clib)
echo "  issuer  = $ISSUER_DID"
echo "  subject = $SUBJECT_DID"
# each agent advertises a DIDComm mailbox (the service lives in the public DID doc)
clia publish-didcomm "$ISSUER_EP"  >/dev/null 2>&1
clib publish-didcomm "$SUBJECT_EP" >/dev/null 2>&1

echo "== PHASE 2: mutual resolution across the peer (no shared registry) =="
clia resolve-did "$SUBJECT_DID" >/dev/null 2>&1; assert "issuer node resolves the subject DID via peer" $?
clib resolve-did "$ISSUER_DID"  >/dev/null 2>&1; assert "subject node resolves the issuer DID via peer" $?

echo "== PHASE 3: issuer mints a credential for the subject =="
clia use-id "$ISSUER" >/dev/null
cat > share/_h_schema.json <<'JSON'
{ "$schema":"http://json-schema.org/draft-07/schema#","type":"object",
  "properties":{ "role":{"type":"string"},"tier":{"type":"string"} },
  "required":["role","tier"] }
JSON
SCHEMA_DID=$(clia create-schema /app/share/_h_schema.json -r local 2>/dev/null | grep -oE 'did:cid:[a-z0-9]+' | head -1)
clia bind-credential "$SCHEMA_DID" "$SUBJECT_DID" 2>/dev/null > share/_h_bound.json
python3 -c 'import json;p="share/_h_bound.json";d=json.load(open(p));d["credentialSubject"].update({"role":"member","tier":"verified"});json.dump(d,open(p,"w"))'
CRED_DID=$(clia issue-credential /app/share/_h_bound.json -r local 2>/dev/null | grep -oE 'did:cid:[a-z0-9]+' | head -1)
[ -n "$CRED_DID" ]; assert "issuer issued a credential ($CRED_DID)" $?
rm -f share/_h_schema.json share/_h_bound.json

echo "== PHASE 4: DELIVER the credential to the subject over DIDComm =="
# <-- Hearthold: replace this line with deliverCredential(transport, subjectDid, credDid) -->
deploy/two-node/pass-card-didcomm.sh "$ISSUER" "$SUBJECT_DID" "$CRED_DID" "$SUBJECT" >/dev/null 2>&1
DELIVER_RC=$?
assert "credential delivered over DIDComm (no shared registry)" $DELIVER_RC

echo "== PHASE 5: subject accepted + can verify, isolation intact =="
clib use-id "$SUBJECT" >/dev/null
clib list-credentials 2>/dev/null | grep -qF "$CRED_DID"; assert "subject agent HOLDS the credential" $?
clib view-credential "$CRED_DID" 2>/dev/null | grep -q 'Proof:.*valid'; assert "credential proof verifies on subject node" $?
# isolation must still hold on both nodes
docker exec "$CLI_A" node -e 'require("http").get({host:"1.1.1.1",port:80,timeout:4000},()=>process.exit(1)).on("error",()=>process.exit(0))' 2>/dev/null; assert "issuer node has NO public egress" $?
docker exec "$CLI_B" node -e 'require("http").get({host:"1.1.1.1",port:80,timeout:4000},()=>process.exit(1)).on("error",()=>process.exit(0))' 2>/dev/null; assert "subject node has NO public egress" $?

echo "== PHASE 6: mutable-identity divergence check (the cache rule) =="
# Issuer updates its DID (adds an alias-driven update). A subject that CACHED the issuer
# will see stale data until reconciled; a subject that resolves FRESH (the target Hearthold
# behavior) would see it immediately. This encodes the offline-first lesson.
clia use-id "$ISSUER" >/dev/null
BEFORE=$(clib resolve-did "$ISSUER_DID" 2>/dev/null | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["didDocument"].get("service",[])))' 2>/dev/null || echo 0)
clia rotate-keys >/dev/null 2>&1   # a benign issuer-side DID update (new version)
V_A=$(clia resolve-did "$ISSUER_DID" 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["didDocumentMetadata"].get("version","?"))' 2>/dev/null)
V_B=$(clib resolve-did "$ISSUER_DID" 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["didDocumentMetadata"].get("version","?"))' 2>/dev/null)
echo "  issuer version on its own node: $V_A | as seen by subject node: $V_B"
if [ "$V_A" = "$V_B" ]; then echo "  NOTE  subject already sees issuer's latest (resolving fresh — ideal)";
else echo "  NOTE  subject sees a STALE issuer (cached copy shadows the peer) — reconcile or, better,"; \
     echo "        never cache the issuer (resolve fresh). This is the Hearthold cache rule."; fi

echo "== RESULT: $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
