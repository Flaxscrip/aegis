# Escalation to macterra: the `local` ↔ `hyperswarm` seam has several core gaps

**From:** Aegis (+ Sevenfold, + Hearthold) · **To:** macterra / Morningstar · **Date:** 2026-07-28

We've been standing up **egress-isolated Hearthold/Archon nodes** and federating two of them (two laptops over
Tailscale) for a real cross-node card-pass. Along the way we kept hitting the same underlying thing from
different angles: **`local` DIDs are isolated but can't do half of Archon's features, and moving to `hyperswarm`
— the only other option — is broken in several specific spots.** We've built workarounds (one worth keeping),
but we'd rather fix the core than keep patching. Every item below is reproduced live; file refs are to
`~/archon` / `@didcid/keymaster` / `@hearthold/core`.

## The core gaps (each reproduced)

1. **`local` identities are barred from authoring ephemeral docs.** `ephemeralRegistry` is hardcoded to
   `hyperswarm` (`keymaster.ts:230`), and `gatekeeper.ts:462` throws `non-local registry=hyperswarm` for a
   `local` identity. So a `local` Sovereign silently **cannot** create challenges/responses, credential-request
   notices, polls/ballots, or dmail — five feature families. (Detail: our `SANDBOX-PROFILE.md §6`.) Net: a truly
   isolated single-node deployment can't run credential accept. That pushes every real node onto `hyperswarm`.

2. **`createId({registry:'hyperswarm'})` on the embedded keymaster still writes a `local` create op.** Proven
   by Sevenfold with *everything* set to hyperswarm: `config.ts:116` (`config.registry = hyperswarm`),
   `keymaster.ts:54` (embedded keymaster `defaultRegistry = config.registry = hyperswarm`), `identity.ts:33`
   (`createId(name, {registry: config.registry})` → explicit hyperswarm) — and `export-did` still shows
   **create registry: local**. Explicit option AND process default both ignored. The **direct keymaster-service
   `POST /api/v1/ids {options:{registry:hyperswarm}}` does NOT have this** (it anchors hyperswarm on the same
   gatekeeper). So the bug is isolated to the **embedded/library create path forcing `local`.** This is the one
   that blocks us right now — a Sovereign minted through Hearthold can't be made gossip-eligible at all.

3. **`change-registry` doesn't make an existing `local` DID gossipable.** `exportBatch` keys gossip-eligibility
   on the **create op's** registry (`gatekeeper.ts:1383`: `events[0].operation.registration.registry !== 'local'`).
   `change-registry` appends a later op but never rewrites `events[0]`, so a `local`-created DID stays
   un-gossipable forever. Migration `local → hyperswarm` is **create-only in practice.** A re-anchor or
   re-export path would fix it.

4. **The peer fallback resolver is confirmed-only, so cross-node nodes can't see each other's updates.**
   `resolveFromUniversalResolver` / `/1.0/identifiers` (`confirm-fallback.ts`) return only the confirmed doc; on
   `hyperswarm` without a mediator, a post-create **update stays unconfirmed** (create auto-confirms, updates
   don't). So node A resolving node B's Sovereign gets the base doc with **no keyAgreement** → can't authcrypt →
   cross-node DIDComm / credential-accept fails. (This is the gap our secure mediator's confirm-on-import works
   around — see below.)

5. *(minor)* The Drawbridge front doesn't proxy `POST /api/v1/events/process` (404), so `processEvents` after a
   write can't go through the same node URL — forced us to inject admin via a side proxy.

## What we built that's worth keeping — `aegis-secure-mediator` (propose upstream?)
The stock `hyperswarm-mediator` (`new Hyperswarm()`, public DHT + UDP holepunch) **can't traverse two different
NATs** (proven megaflax↔gamerflax: `Connected nodes: 0`), churns its swarm every 60s while unconnected, and
gossips `getDIDs()` = the whole node to anyone who knows the topic. Our drop-in (`deploy/secure-mediator/`, uses
the public `@didcid/*` HTTP API, no core changes) adds four properties and is **proven live** (two laptops,
`AUTH OK`, a keyAgreement update crossing and becoming resolvable):
1. **Tailnet transport** — private `hyperdht` (seed + `firewalled:false` + bind) → direct over WireGuard, no
   public DHT/holepunch, stable.
2. **Peer auth** — a peer joins only by proving an allowlisted member node DID (challenge → `/keys/sign` →
   `/keys/verify` + allowlist + fresh nonce).
3. **Scoped gossip** — only an allowlisted DID set crosses (not the whole node).
4. **Confirm-on-import** — `processEvents` after `batch/import`, so a synced update actually lands (works around
   gap #4). Would love your view on whether this belongs in core / the stock mediator.

## Temporary workarounds we want to retire (they exist only because of the gaps above)
- **Direct keymaster-service pre-mint** of the Sovereign (dodges gap #2). Retire when #2 is fixed.
- **Admin-injecting node proxy** (`nodeurl-proxy.mjs`) for `processEvents` writes (gap #5).
- **`confirm-on-import`** as a substitute for real cross-node update propagation (gap #4) — arguably it becomes
  a legit mediator feature; your call.
- socat loopback forwarders (deployment plumbing for `internal:true` nets + macOS Docker; keep as a pattern).

## Asks
- **#2 first** (it's blocking): why does the embedded `createId` force `local` when both explicit and default are
  `hyperswarm`, while the service API doesn't? That's the immediate unblock for federated Hearthold.
- Then **#1, #3, #4** — collectively they'd let a node be *isolated by default and federate cleanly when it
  chooses*, which is exactly the product we're building toward (a one-command isolated Sovereign that can join a
  family/corporate sphere).
- And whether the **secure-mediator** properties belong upstream.

Happy to demo any of these live on the two-laptop rig.
