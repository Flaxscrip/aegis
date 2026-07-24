# Aegis findings: wiring Hearthold cross-node credential delivery on the isolated two-node substrate

Reciprocal to `~/hearthold/docs/credential-delivery/{AEGIS-HANDOFF,INTEGRATION,FINDINGS}.md`.
**Result: the mechanism works end-to-end on two isolated nodes with no shared registry —
`accepted: true`, and `hearthold-sovereign` holds the delivered VC on node B, fully offline
(every container `ENETUNREACH`).** Getting there required three accommodations; two are
Hearthold/Archon-core gaps, one is substrate glue Aegis now owns.

## Topology used
- **Issuer** = `hearthold-warden` on node A (container on `archon_default`, `HEARTHOLD_NODE_URL=http://drawbridge:4222`).
- **Subject** = `hearthold-sovereign` on node B (container on `aegis-peer`, serving `serve-credential-delivery.ts`).
- Cross-node DIDComm over the `aegis-peer` link; issuer/subject resolve each other via the gatekeeper peer fallback.
- Glue (this dir): `provision.mjs` (ensure role identity), `issue.mjs` (warden mints the membership VC),
  `nodeurl-proxy.mjs` (see finding #1).

## Answer to the explicit ask: **`--include-issuer-ops` is REQUIRED.**
Default delivery (ships only VC+schema ops, resolves issuer fresh) → `accepted: false`
("VC not resolvable/decryptable"). The subject's gatekeeper cannot verify the imported VC
without the **issuer present locally**, because Archon core's `verifyOperation` resolves the
controller with a **local-only** `resolveDID` (`gatekeeper.ts:460`) — the peer fallback is a
server-layer wrapper the core never calls. So the cache-rule ideal (never ship the issuer) is
**blocked by core today**. → **macterra escalation priority: HIGH** (peer-fallback-capable
`verifyOperation` + `versionTime` is what removes the throwaway).

## Finding #1 — `/api/v1/dids/import` is NOT reachable via the subject's `HEARTHOLD_NODE_URL`
On an isolated node the subject's `nodeUrl` must be **Drawbridge** (it's the DIDComm gateway).
But `GatekeeperClient.importDIDs` POSTs `${nodeUrl}/api/v1/dids/import`, and:
- via **Drawbridge :4222** → **404** (Drawbridge proxies `/dids` and `/dids/export` but **not** `/dids/import`).
- via the **raw gatekeeper :4224** → **401** (`requireAdminKey`; the Hearthold client passes no `apiKey`).

So import silently fails; the handler's best-effort catch then finds the VC only via fallback
(stripped, no `didDocumentData`) → cannot decrypt → `accepted: false`.

**This is the `HEARTHOLD_GATEKEEPER_URL` decoupling your docs reference but `config.ts` doesn't wire.**
Cleanest fix (Hearthold): give the handler a **separate** import gatekeeper client pointed at the
raw gatekeeper, constructed with `GatekeeperClient.create({ url, apiKey })` (the `apiKey` option
already exists → sets `X-Archon-Admin-Key`). Keep `nodeUrl` = Drawbridge for keymaster/DIDComm.

**Aegis workaround (works with the UNMODIFIED script):** `nodeurl-proxy.mjs` — a tiny node proxy
the subject points `HEARTHOLD_NODE_URL` at. It routes `/api/v1/dids/import` → raw gatekeeper (injecting
the admin key) and everything else → Drawbridge. The substrate absorbs the split.

## Finding #2 — `importDIDs` QUEUES; the handler never PROCESSES, so imports don't apply in time
Even with `--include-issuer-ops` and a reachable import endpoint, delivery returned `accepted: false`.
`gatekeeper.importDIDs` **queues** operations (`queued: N, processed: 0`); they are not applied until
`processEvents` runs. The handler imports then immediately checks/accepts, so within the delivery
window the VC is still unapplied → not locally resolvable → accept fails. Running `process-events` on
node B applied the ops (`added: 5, pending: 0`), the VC then resolved locally **with `didDocumentData`**,
and a **re-delivery returned `accepted: true`** with the VC held.

This was masked on your single-node 11/11 (shared registry → the VC is already resolvable, so import
short-circuits and the queue is never exercised). **Fix (Hearthold or core):** after `importDIDs`, call
`processEvents` (or have `importDIDs` apply synchronously / the handler poll-until-resolvable before
accepting).

## What a fully-automated harness PHASE-4 needs, until #1/#2 land
`deliver --include-issuer-ops` → trigger `process-events` on the subject node → poll deliver until
`accepted`. With the two Hearthold fixes above (and macterra's core fix removing `--include-issuer-ops`),
it collapses to the clean single call the seam envisions.

## Isolation
Preserved throughout — issuer node, subject node, the subject container, and the node-URL proxy all
`ENETUNREACH` to the public internet. Cross-node delivery rode only the internal `aegis-peer` link.
