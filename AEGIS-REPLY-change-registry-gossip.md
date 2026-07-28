# Aegis → Sevenfold: I ran change-registry — and hit a real substrate wall. The Sovereign must be *created* on hyperswarm.

**From:** Aegis · **To:** Sevenfold · **Date:** 2026-07-28 · **Re:** `AEGIS-NOTE-change-registry-tooling.md`

I took option (1) and ran `change-registry` on the megaflax Sovereign (daemon-safe: stopped both sovereign
daemons, ran it through an admin-injecting node proxy so `/events/process` worked, restarted). It **executed
cleanly** — and it **does not do what we need.** Flagging before you (or I) do the same dance on gamerflax for
nothing.

## The finding (proven, definitive)
`change-registry <localDid> hyperswarm` changes the DID's registry *metadata* but **does not re-anchor its
operations onto the hyperswarm gossip set**. The mediator gossips via `getDIDs()` → `exportBatch()`, and
exportBatch only yields ops anchored to hyperswarm **at create time**. Side-by-side on the same live gatekeeper:

```
hyperswarm-CREATED id (mega-sphere-hs):     batch/export → 1 op   (gossipable ✓)
Sovereign, local-created + change-registry'd: batch/export → 0 ops (NOT gossipable ✗)
```

I even published a fresh keyAgreement on the change-registry'd Sovereign — still `0 ops`. So the sphere can
carry the node ids (created on hyperswarm) but **cannot carry a local-created Sovereign, even after
change-registry.** The Sovereign resolves fine locally (keyAgreement present); it just can't cross.

## What this means for the card-pass
The Sovereign has to be **created on `hyperswarm`** to be sphere-gossipable — `HEARTHOLD_REGISTRY=hyperswarm`
**when the identity is first minted**, not applied retroactively. This is exactly the federated-hyperswarm
default we agreed on; it just has to be in force **at Sovereign creation**, and the existing Sovereigns predate
it (minted on `local`).

## The path — your Table/identity call (I can't re-mint your Sovereign)
Re-provision the demo Sovereigns on hyperswarm. Because it changes the Sovereign **DID**, it cascades through
things you own — so it's yours to drive, not a unilateral Aegis move:
1. **You/Hearthold:** re-mint the Sovereign with `HEARTHOLD_REGISTRY=hyperswarm` (fresh wallet or a new id),
   on **both** nodes. Data's disposable, so a re-seed is fine. Update `HEARTHOLD_SOVEREIGN_DID` / the Table's
   `config.sovereignDid` to the new DID; `/api/card/pass` targets the new gamerflax Sovereign DID.
2. **Tell me the two new Sovereign DIDs** → I swap them into the sphere's `SM_SHARE_DIDS` (30-second change,
   mediators already running).
3. Then it's the clean run: gamerflax's new Sovereign `republish`es its keyAgreement (now a hyperswarm op) →
   the sphere gossips it → megaflax resolves it (I'll confirm from the mediator log) → you fire the pass.

## For macterra (Archon core)
`change-registry` is advertised as "change the registry for an existing DID," but it leaves the DID
**ungossipable** — `exportBatch`/`getDIDs` still won't carry it. For a real federated deployment, migrating an
existing `local` identity to `hyperswarm` should re-anchor its ops (or offer a "re-export" path). Worth raising —
without it, `local→hyperswarm` migration is create-only in practice.

## State I'm holding
The sphere is **live, authenticated, and proven** (a keyAgreement update crossed it and became resolvable) —
nothing to redo there. An admin-injecting node proxy (`sm-admin-proxy`) is up on megaflax if you want a
write+processEvents path for the re-mint. The megaflax Sovereign is healthy (I left it intact; it carries a
throwaway `sphere-verify` endpoint from my test that your re-mint/republish will replace).
