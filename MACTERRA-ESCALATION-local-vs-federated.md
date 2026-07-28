# Escalation to macterra: make `local`-first identities cleanly promotable to `hyperswarm`/spheres

**From:** Aegis (+ Sevenfold, + Hearthold) · **To:** macterra / Morningstar · **Date:** 2026-07-28
**Status:** revised after independent source validation — one earlier claim was ours (a misread), corrected below.

## The product we're building toward
A Sovereign should be able to run **`local`-first** (fully isolated, no gossip) and later **promote** their
identity/documents into a `hyperswarm` **sphere** (family/corporate) when they choose. `local` is a *feature* we
want — the issue is that the `local → hyperswarm` path has real gaps. Everything below is reproduced against
`~/archon`; file refs included. We independently re-verified each before sending.

## What we RETRACT (was our misread, not a core bug)
We previously flagged "the embedded `createId` forces a `local` create op even with explicit + default =
hyperswarm." **That is wrong.** `gatekeeper.ts:590` stamps every stored event's **top-level** `registry: 'local'`
by design (it's the local-DB storage marker); the DID's real registry lives in
`operation.registration.registry`, which `createIdOperation` (`keymaster.ts:1636`, `const {registry =
this.defaultRegistry} = options`) sets correctly and `queueOperation` distributes on. Verified end-to-end: an
`@hearthold/core` `ensureIdentity` mint with `HEARTHOLD_REGISTRY=hyperswarm` produces
`operation.registration.registry = hyperswarm` and **exports/gossips fine.** We'd been reading the wrong field
(`export-did` surfaces the top-level `local`). No bug here — but a sharp **observability trap**: tooling that
shows a DID's "registry" as the event's `local` marker will mislead everyone. A surfaced *effective* registry
(the create op's) would prevent this.

## The REAL gaps

1. **`local` identities can't author ephemeral / credential docs — so no VCs, challenges, dmail, polls on a
   fully-`local` node.** `ephemeralRegistry` is hardcoded `'hyperswarm'` (`keymaster.ts:209`, used at
   `:3415/:3631`), and `gatekeeper.ts:462` enforces controller-vs-asset consistency: a `local`-registered
   identity may not author a non-`local` operation. So the ephemeral doc (always hyperswarm) is refused for a
   `local` controller. Net: a truly isolated single-node Sovereign **cannot issue/accept a credential.** This is
   the core tension — `local` is only half a citizen. Options we'd love your take on: let `ephemeralRegistry`
   follow the identity's registry; or permit ephemeral (short-lived, `validUntil`) assets under a `local`
   controller; or a first-class "promote this identity" op.

2. **`change-registry` doesn't actually make a `local`-created DID gossipable — promotion is create-only in
   practice.** `exportBatch` keys gossip-eligibility on the **create op's** registry
   (`gatekeeper.ts:1383`: `events[0].operation.registration.registry !== 'local'`). `change-registry` appends a
   later op but never rewrites `events[0]`, so a `local`-created DID stays un-gossipable forever (verified: a
   change-registry'd Sovereign exports 0 ops; a hyperswarm-*created* one exports its op). For "local-first,
   promote later" to work, `change-registry` needs to re-anchor (or a re-export path is needed).

3. **The peer fallback resolver is confirmed-only, so two isolated `hyperswarm` nodes can't see each other's
   post-create updates.** `/1.0/identifiers` / `confirm-fallback.ts` return only the confirmed doc; on
   `hyperswarm` without a mediator a create auto-confirms but an **update stays unconfirmed**. So node A resolving
   node B's Sovereign sees the base doc with **no keyAgreement** → can't authcrypt → cross-node DIDComm fails.
   (We work around this — see the mediator.)

4. *(minor)* The Drawbridge front doesn't proxy `POST /api/v1/events/process` (404), so a post-write
   `processEvents` can't traverse the same node URL; forced an admin side-proxy.

## What we built worth keeping — `aegis-secure-mediator` (propose upstream?)
The stock `hyperswarm-mediator` can't traverse two NATs (proven megaflax↔gamerflax: `Connected nodes: 0`),
churns every 60s, and gossips the whole node to anyone on the topic. Our drop-in (public `@didcid/*` HTTP API,
no core changes; **proven live** — two laptops, `AUTH OK`, a keyAgreement update crossing and becoming
resolvable) adds: **tailnet transport** (private `hyperdht`, direct over WireGuard), **peer auth** (allowlisted
member node DID via `/keys/sign`+`/keys/verify`), **scoped gossip** (only an allowlisted DID set crosses), and
**confirm-on-import** (`processEvents` after `batch/import` — works around gap #3). Worth upstreaming?

## Asks (in priority)
- **#1** — the local-can't-author-ephemeral invariant is what makes `local` "half a citizen." A way to VC/accept
  under `local` (or a clean promote op) is the single biggest unblock for isolated-Sovereign product.
- **#2** — `change-registry` should re-anchor for gossip, so "local-first, promote later" actually works.
- **#3** — cross-node visibility of unconfirmed updates (or bless mediator confirm-on-import as the path).
- The **observability trap** (surface the effective/create-op registry, not the event's `local` marker).
- Whether the **secure-mediator** belongs upstream.

Happy to demo any of it live on the two-laptop rig.
