# Aegis findings: wiring Hearthold cross-node credential delivery on the isolated two-node substrate

Reciprocal to `~/hearthold/docs/credential-delivery/{AEGIS-HANDOFF,INTEGRATION,FINDINGS}.md`.
**Result: `deploy/two-node/harness-hearthold-delivery.sh` passes 11/11 — cross-node delivery
through Hearthold's real primitives, single `deliver-credential.ts` call, `accepted: true`,
`hearthold-sovereign` holds the VC on node B, fully offline (every container `ENETUNREACH`).**

Status of the three items from the first pass:
- **Finding #2 (process-after-import): FIXED by Hearthold** — `credential-delivery.ts:178` now calls
  `processEvents()` after `importDIDs`. ✓
- **Finding #1 (admin/DB endpoints not reachable via `nodeUrl`): still open** — and BROADER than first
  reported (it's not just `/dids/import`; `processEvents` and every gatekeeper admin/DB op have the same
  problem). Absorbed substrate-side by the node-URL proxy (below).
- **`--include-issuer-ops`: still REQUIRED** — the Archon-core item (macterra).

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

## Finding #1 (OPEN) — gatekeeper admin/DB endpoints aren't reachable via the subject's `HEARTHOLD_NODE_URL`
On an isolated node the subject's `nodeUrl` must be **Drawbridge** (it's the DIDComm gateway).
But `GatekeeperClient.importDIDs` POSTs `${nodeUrl}/api/v1/dids/import`, and:
- via **Drawbridge :4222** → **404** (Drawbridge proxies `/dids` and `/dids/export` but **not** `/dids/import`).
- via the **raw gatekeeper :4224** → **401** (`requireAdminKey`; the Hearthold client passes no `apiKey`).

The same is true of **`processEvents`** and every gatekeeper admin/DB endpoint — Drawbridge simply doesn't
proxy them. So with the handler's new `processEvents()` call routed through `nodeUrl` (Drawbridge), it too
404s: import queues but never applies → VC only via fallback (stripped, no `didDocumentData`) → `accepted: false`.

**This is the `HEARTHOLD_GATEKEEPER_URL` decoupling your docs reference but `config.ts` doesn't wire.**
Cleanest fix (Hearthold): give the handler a **separate** gatekeeper client for import/processEvents,
pointed at the raw gatekeeper, constructed with `GatekeeperClient.create({ url, apiKey })` (the `apiKey`
option already exists → sets `X-Archon-Admin-Key`). Keep `nodeUrl` = Drawbridge for keymaster/DIDComm.

**Aegis workaround (works with the UNMODIFIED script):** `nodeurl-proxy.mjs` — a tiny node proxy the subject
points `HEARTHOLD_NODE_URL` at. It routes `/didcomm/*` → Drawbridge and **everything else** → the raw
gatekeeper (injecting the admin key). Resolve isn't admin-gated (the key is harmless); import/processEvents
require it; the raw gatekeeper carries the peer fallback so cross-node resolution still works. This is the
substrate absorbing the split, and it makes the current unmodified scripts pass 11/11.

## What the clean single-call PHASE-4 needs
With Hearthold's `processEvents` fix already in, the automated seam is a **single `deliver-credential.ts
--include-issuer-ops` call** (see `harness-hearthold-delivery.sh`) given the node-URL proxy. Dropping the
proxy needs Hearthold to wire the import/processEvents client decoupling (finding #1). Dropping
`--include-issuer-ops` needs macterra's core `verifyOperation` peer-fallback fix.

## Isolation
Preserved throughout — issuer node, subject node, the subject container, and the node-URL proxy all
`ENETUNREACH` to the public internet. Cross-node delivery rode only the internal `aegis-peer` link.
