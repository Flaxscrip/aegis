#!/usr/bin/env bash
#
# pass-card-didcomm.sh — pass a verifiable credential ("a card") from one isolated
# Aegis node to another over DIDComm, fully offline, across the aegis-peer link.
#
# WHERE THIS BELONGS (Aegis vs Hearthold): this is an AEGIS script — it exercises the
# isolated two-node TRANSPORT by exec'ing into the aegis containers (like the roleplay
# wrappers). The card-passing PROTOCOL itself (bundle shape, send/accept semantics) is
# application logic that belongs in Hearthold/Sevenfold and should work on ANY Archon
# deployment; Aegis only provides the egress-isolated substrate it runs on.
#
# PREREQUISITES (one-time wiring, already in deploy/two-node/):
#   - node A in peer mode with didcomm joined to aegis-peer (docker-compose.peer.yml)
#   - node A didcomm has ARCHON_DIDCOMM_ALLOW_PRIVATE_EGRESS=true (base override)
#   - recipient has published a DIDComm endpoint reachable on the peer:
#       clib publish-didcomm http://drawbridge-b:4222/didcomm
#   - SENDER has published one too (needed as authcrypt sender):
#       clia publish-didcomm http://drawbridge:4222/didcomm
#
# WHY a "bundle" and not just the card DID: cross-node RESOLUTION carries only public DID
# docs, never a VC's encrypted didDocumentData (identifiers-router.ts:72). So the card's
# CONTENT must travel in the DIDComm message. We ship the card + the DIDs needed to import
# and verify it. NOTE (chatty-protocol principle): the ISSUER Agent DID is included ONLY
# because the core gatekeeper's asset-import verify (verifyOperation -> local-only
# resolveDID) currently needs the controller present locally. Identities are MUTABLE, so a
# cached copy goes stale (issuer key rotation / new services) — the moment Archon core lets
# import verify resolve the issuer over the peer fallback, drop the issuer from the bundle
# and resolve it FRESH each time. The card + schema are immutable, so caching them is safe.
#
# Usage:  pass-card-didcomm.sh <sender-id-name> <recipient-DID> <vc-DID>
set -euo pipefail
SENDER="${1:?sender identity name (e.g. ada)}"
RECIPIENT="${2:?recipient DID}"
VC="${3:?VC (card) DID}"

# containers (override for a real two-machine LAN split)
CLI_A="${AEGIS_CLI_A:-archon-cli-1}"          # sender node
CLI_B="${AEGIS_CLI_B:-aegisb-cli-b-1}"         # recipient node
SHARE="${AEGIS_SHARE:-share}"                   # host dir mounted at /app/share in BOTH clis
cd "$(dirname "$0")/../.."                       # repo root

clia(){   docker exec "$CLI_A" node scripts/archon-cli.js "$@"; }
admin_a(){ docker exec "$CLI_A" node scripts/admin-cli.js "$@"; }
clib(){   docker exec "$CLI_B" node scripts/archon-cli.js "$@"; }
admin_b(){ docker exec "$CLI_B" node scripts/admin-cli.js "$@"; }

echo "== SENDER ($SENDER on $CLI_A): assemble card bundle + send over DIDComm =="
# Guard: the CLI's `use-id` prints "Unknown ID" but still EXITS 0, so a typo'd sender would
# silently send as whatever identity is current. Verify the name exists before trusting it.
clia list-ids 2>/dev/null | sed 's/ *<<< current//' | grep -qxF "$SENDER" \
  || { echo "  sender identity '$SENDER' not found on $CLI_A (list-ids)"; exit 1; }
clia use-id "$SENDER" >/dev/null
ISSUER=$(clia resolve-id 2>/dev/null | grep -m1 '"id": "did:cid:' | grep -oE 'did:cid:[a-z0-9]+')
SCHEMA=$(clia view-credential "$VC" 2>/dev/null | awk '/^Schema:/{print $2}')
: "${SCHEMA:?could not read schema DID from the card}"

admin_a export-did "$ISSUER" > "$SHARE/_x_issuer.json"
admin_a export-did "$SCHEMA" > "$SHARE/_x_schema.json"
admin_a export-did "$VC"     > "$SHARE/_x_card.json"
CARD="$VC" python3 - "$SHARE" <<'PY'
import json,os,sys
share=sys.argv[1]
def ops(n): return json.load(open(f"{share}/_x_{n}.json"))[0]   # exportDIDs -> [[events]]
msg={"type":"https://sevenfold.local/card-transfer",
     "body":{"card":os.environ["CARD"],
             "note":"card passed over DIDComm",
             # importDIDs-shaped [[events],...]; issuer first so its deps resolve on import
             "bundle":[ops("issuer"),ops("schema"),ops("card")]}}
json.dump(msg,open(f"{share}/_x_msg.json","w"))
PY
clia send-didcomm --sign /app/share/_x_msg.json "$RECIPIENT"
rm -f "$SHARE"/_x_issuer.json "$SHARE"/_x_schema.json "$SHARE"/_x_card.json "$SHARE"/_x_msg.json

echo "== RECIPIENT (on $CLI_B): receive, import bundle, accept card =="
clib receive-didcomm 2>/dev/null > "$SHARE/_x_inbox.json"
FOUND=$(python3 - "$SHARE" "$VC" <<'PY'
import json,sys
share,vc=sys.argv[1],sys.argv[2]
for m in json.load(open(f"{share}/_x_inbox.json")):
    msg=m.get("message",{})
    if msg.get("type","").endswith("card-transfer") and msg.get("body",{}).get("card")==vc:
        json.dump(msg["body"]["bundle"],open(f"{share}/_x_bundle.json","w"))
        print("yes"); break
else:
    print("no")
PY
)
if [ "$FOUND" != "yes" ]; then echo "  card $VC not found in recipient inbox"; rm -f "$SHARE"/_x_inbox.json; exit 1; fi
admin_b import-did /app/share/_x_bundle.json >/dev/null
admin_b process-events >/dev/null
# accept-credential accepts for the recipient node's CURRENT id, which must be the card's
# subject. Set it first if a recipient name is given (4th arg), else assume it's current.
[ -n "${4:-}" ] && clib use-id "$4" >/dev/null
clib accept-credential "$VC"
echo "-- recipient now holds the card --"
clib view-credential "$VC" 2>/dev/null | sed -n '1,20p'
rm -f "$SHARE"/_x_inbox.json "$SHARE"/_x_bundle.json
