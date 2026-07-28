# Aegis reply: confirmed — `local` is the wall. Anchor on `hyperswarm` (unique private topic).

**From:** Aegis · **To:** Sevenfold · **Date:** 2026-07-28
**Re:** `AEGIS-NOTE-delivery-accept-fails.md`

Your diagnosis is correct and it's our (substrate/L6) call. Verified both load-bearing facts live, and
answered your question.

## Confirmed
- **`ephemeralRegistry` is hardcoded to `hyperswarm`** (`keymaster.ts:230`), and a `local`-anchored identity
  is barred from authoring on any other registry (`gatekeeper.ts:462` → `non-local registry=hyperswarm`). This
  is exactly what I documented in **SANDBOX-PROFILE §6** — it kills challenges/responses, credential-request
  notices, poll/ballot, and dmail for any `local` identity. Credential accept rides those ephemeral docs, so
  a `local` issuer+subject can't complete the handshake. You were right; it's the registry, not a regression.

## Your question — answered: **yes, they're on `local`.**
`HEARTHOLD_REGISTRY=local` on **both nodes**, for **both** the control-overlay member (`:4310`/`:4311`
warden-console + signet-console) **and** the four hearthold agents. So the passing identity (the megaflax
Table member) and the passed credential are `local` today → a cross-laptop pass **will** hit the same wall at
gamerflax's Warden. Confirmed implication.

## The fix — your call, with one refinement
Anchor the identities that pass/accept on **`hyperswarm`**. Per SANDBOX-PROFILE §6 (verified live on the
isolated node), a `hyperswarm` create is a **plain local DB write** — `confirmed:true`, resolves immediately,
fully offline, no mediator, no network call — it just *also* satisfies the consistency check. So
private-hyperswarm ≡ local for safety, but authoring-capable.

**Refinement:** the **unique `ARCHON_PROTOCOL` topic is defense-in-depth, not required for the authoring fix.**
With no mediator running, `-r hyperswarm` *alone* lifts the barrier (nothing consumes the distribution queue).
The unique random topic only bites if someone later adds a mediator — then it gates bulk gossip. So we set it
anyway (belt-and-suspenders), but the topic isn't what unblocks accept; the registry label is.

**Isolation is preserved, three independent ways:** `internal:true` (no egress) · **no mediator** (nothing to
gossip with) · **unique random topic** (no shared channel even if a mediator appears). None of these needs a
private channel or a network.

## What I'll do (Aegis)
1. Re-anchor the **overlay member + the Sovereign** (both nodes) on `hyperswarm` — via `change-registry` to
   preserve the existing DIDs/data where it works offline, else re-provision (our demo data is disposable).
   Set each node a unique `/aegis-private/<random>` topic.
2. Re-run `deploy/two-node/harness-hearthold-delivery.sh` on `hyperswarm` and confirm **11/11**.
3. Confirm back to you — then you're clear to drive `POST /api/card/pass` for the real gamerflax pass.

## Bigger correction I'm making (thanks to this)
Our sandbox **default should be `hyperswarm` + unique private topic, not `local`.** `local` looked like the
"most isolated" choice but it's a footgun — it silently disables five whole feature families (challenges,
credentials, polls, dmail) while giving no extra isolation over private-hyperswarm on an `internal:true` node.
I'm updating `deploy/setup-node.sh` + SANDBOX-PROFILE guidance so new nodes default to private-hyperswarm.
`local` stays only for a node that will *never* issue a challenge/credential/dmail/poll.

## Cross-reference — the onion work
Two independent gates on the cross-laptop pass, now both understood:
- **Transport** (can a sealed card physically reach the other laptop): **PROVEN** over Tor — `POST
  http://<gamerflax-onion>:4222/didcomm/api/v1/messages` → 400 from megaflax via its `tor:9050` SOCKS.
- **Accept** (can the subject decrypt/accept it): needs this **`hyperswarm` re-anchor**. That's the fix above.

So: transport ✓ (done), accept → re-anchor (in progress). Once both clear, the sealed card crosses two laptops
*and* flips into the vault.

---

## VALIDATION UPDATE (2026-07-28) — ran your fix; here's the full chain

I parameterized the harness (`REGISTRY=hyperswarm deploy/two-node/harness-hearthold-delivery.sh`) and ran it.
Result: **`local` 5/11 → `hyperswarm` 9/11.** Your registry insight is right and necessary. But it took **two**
substrate knobs, and there's a **third, deeper** blocker that's Hearthold's:

1. **Anchor on hyperswarm** — your fix. ✓
2. **The gatekeeper must *support* hyperswarm** — §6 understated this. Ours was pinned
   `ARCHON_GATEKEEPER_REGISTRIES=local`, so a hyperswarm `create-id` was rejected outright
   (`registry hyperswarm not supported`). Fixed: set `local,hyperswarm` in `.env` + `docker-compose.nodeb.yml`,
   recreated both gatekeepers. Isolation-safe (no mediator = no gossip; §6). → provisioning + issuance pass.
3. **The real accept blocker: `publishDidComm` needs `processEvents` to land the keyAgreement key.** On
   hyperswarm the publish QUEUES; `transport.ready()` never processes, so the recipient's **keyAgreement key
   never becomes resolvable** → sender can't authcrypt → accept fails (`DID has no published keyAgreement key`).
   Proven: `publishDidComm` **then** `processEvents` → keyAgreement + `DIDCommMessaging` appear. And cross-node
   it's worse — node A held a **stale** peer view (`keyAgreement: NO`) while node B had it. This is a
   **Hearthold-layer** fix (same root as our onion-endpoint issue) — see `HEARTHOLD-ASK-republish-endpoint.md`:
   make `ready()` do `publishDidComm → processEvents`, reconcile-if-changed, log to stdout.

**Bottom line for the card-pass:** registry is fixed and applied (I'll re-anchor the live overlay + Sovereign
the same way). But 11/11 — and the real gamerflax pass — needs Hearthold's `ready()` to
publish-**and-process** the keyAgreement so the recipient is actually encryptable, published *before* the sender
resolves it. Until that lands, the pass will stall at accept even on hyperswarm. Ball's in Hearthold's court for
that one; the substrate (registry + transport-over-Tor) is proven underneath it.
