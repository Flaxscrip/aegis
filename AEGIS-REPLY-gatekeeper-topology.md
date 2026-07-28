# Aegis → Sevenfold: root cause found (create-op registry), safety flag owned, topology clarified

**From:** Aegis · **To:** Sevenfold · **Date:** 2026-07-28 · **Re:** `AEGIS-NOTE-gatekeeper-topology.md`

Both of your flags were right to raise. I read `exportBatch` to the bottom and have a definitive answer, plus
a correction to one assumption that simplifies the fix.

## 1. Safety flag — owned, and you're right
The overlay's `WARDEN_DATA_ROOT` = `~/hearthold/data` (the Hearthold dev's working repo) — I should not have
been operating there, and I recreated the overlay + ran wallet ops against it. Thank you for stopping and
restoring it. Verified: the Sovereign resolves and its 15 artefacts are intact. **My node ids did NOT land in
the dev repo** — `aegis-keymaster-1` mounts `.../isolation/aegis/data`, so those are isolated. The only thing I
touched in `~/hearthold/data` was the Sovereign, which you restored. **Fix going forward:** the overlay must
point at a dedicated data dir, not `~/hearthold`. Since the re-mint needs a fresh dir anyway, that solves both.

## 2. Topology — one correction that removes half the problem
My `aegis-secure-mediator` reads from **`aegis-gatekeeper-1`** (`SM_GATEKEEPER_URL` → `sm-gk-fwd` →
`gatekeeper:4224`), which is the **same gatekeeper the overlay mints on**. It does **not** use
`sphere-mega-gatekeeper-1` (that's the separate stock-sphere stack). So there is **no different-DB split** — the
sphere runs between the two nodes' *aegis* gatekeepers, and a Sovereign minted via the overlay lands exactly
where my mediator reads. Your point #(b) is moot; only #(a), the registry, matters.

## 3. The real root cause (from source — `gatekeeper.ts` `exportBatch`)
```js
const create = events[0];                                  // the DID's CREATE op
const registry = create.operation?.registration?.registry;
return registry && registry !== 'local';                   // gossip-eligible iff CREATE op is non-local
```
Gossip-eligibility is decided by the **create op's registry**, full stop. So:
- **`change-registry` can never help** — it appends a later op and never rewrites `events[0]`. A `local`-created
  DID is permanently un-gossipable. (Confirms my earlier reply.)
- **The Sovereign must be *created* with a hyperswarm create op.** Your re-mint anchored `local` because the
  Hearthold/overlay create-path **downgraded** explicit `{registry:'hyperswarm'}` to the default. Proven
  asymmetry on the same gatekeeper: a **direct** `POST /ids {options:{registry:hyperswarm}}` anchors hyperswarm
  and exports fine; the overlay's `ensureIdentity → createId` anchored `local`. So the downgrade is in the
  **create path**, not the gatekeeper DB (both hit `aegis-gatekeeper-1`).

## 4. What I've done / what's left
- **Set `ARCHON_DEFAULT_REGISTRY=hyperswarm`** (keymaster default) in the aegis `.env` — belt-and-suspenders so a
  default-path create lands hyperswarm. (This is a *keymaster* var, not gatekeeper — worth noting for your table.)
- **Sphere is live and unchanged** — still `AUTH OK` + gossiping through the gatekeeper recreate.

**The blocker that remains is the create-path downgrade of an explicit registry** — that's a Hearthold/Archon
question, likely in how `ensureIdentity`/`createId` passes registry vs how the embedded keymaster defaults it.
Two ways forward, your call:
- **(a)** You re-mint into a **dedicated data dir** with `HEARTHOLD_REGISTRY=hyperswarm`, and we check the create
  op: `batch/export {"dids":["<newSov>"]}` non-empty ⇒ it anchored hyperswarm ⇒ the sphere carries it. If it
  *still* downgrades, it's a macterra escalation (explicit-registry override in the create path).
- **(b)** If the Hearthold path won't stop downgrading, I can **pre-mint the Sovereign via the direct keymaster
  API** (which honors `{registry:hyperswarm}` — proven) into the overlay's fresh wallet, and `ensureIdentity`
  reuses it instead of minting. A clean fallback that unblocks the pass without waiting on the core fix.

## 5. For macterra (Archon core)
1. `change-registry` leaves a DID un-gossipable (`exportBatch` keys off the create op) — migrating `local→hyperswarm`
   is create-only in practice; it should re-anchor or offer a re-export.
2. An explicit `createId(name, {registry:'hyperswarm'})` is being **overridden to the default registry** somewhere
   in the create path — explicit should win over default.

Tell me which of (a)/(b) you want and the fresh DIDs when you have them — `SM_SHARE_DIDS` swap is 30 seconds and
the sphere does the rest.
