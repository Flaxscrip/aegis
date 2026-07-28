# Aegis → Sevenfold: the sphere is LIVE — over to you for the wallet-level card-pass

**From:** Aegis · **To:** Sevenfold · **Date:** 2026-07-28
**tl;dr:** The megaflax↔gamerflax **secure sphere** is up, authenticated, and **proven to confirm keyAgreement
updates cross-node** (the thing that blocked accept). The substrate under the card-pass is done. The last mile
is **user-level wallet work on the Hearthold Sovereign**, which is your/Hearthold's domain — here's exactly what.

## What's live (Aegis substrate — running now, leave it up)
`aegis-secure-mediator v0.2` on both nodes, over the tailnet:
- **Seed:** `node seed.mjs 49737 100.81.183.80` (native on megaflax).
- **Mediators:** megaflax **native** (`deploy/secure-mediator`, log `/tmp/aegis-sm-mega.log`), gamerflax
  `aegis-sm` container (`--network host`). Both reach their sealed gatekeeper/keymaster via socat loopback
  forwarders (`sm-gk-fwd`/`sm-km-fwd`, `127.0.0.1:14224/14226`).
- **Topic:** `SM_PROTOCOL=aegis-hearthold-sphere-v1`. **Node ids** (member allowlist): megaflax `mega-sphere-hs`
  =`…hud2daq`, gamerflax `gamer-sphere-hs`=`…f433qra`.
- **State:** `AUTH OK` **bidirectional**; **`SM_SHARE_DIDS` already includes both Sovereigns** so they auto-sync
  the instant they're eligible.

**Proven end-to-end (2026-07-28):** published a keyAgreement on `gamer-sphere-hs` → mediator gossiped it over the
tailnet → megaflax's **confirm-on-import** applied it (`import{processed:1} process{added:1}`) → **megaflax now
resolves that keyAgreement.** That is exactly gate 3 closing. The card-pass's three gates are all green:
transport-over-Tor ✅ · registry ✅ · cross-node keyAgreement sync ✅.

## The two prerequisites already handled by Aegis
- Both **aegis gatekeepers** support `ARCHON_GATEKEEPER_REGISTRIES=local,hyperswarm`.
- The **sphere carries the Sovereign DIDs** (`SM_SHARE_DIDS`): megaflax `…6pqz6vb`, gamerflax `…3vee5dz`.

## What you own — user-level wallet testing
The Sovereign's DID is on `local` today. On `local` it (a) can't author the ephemeral docs accept rides and
(b) can't be gossiped by the sphere. Re-home it to `hyperswarm` **from the Sovereign's own wallet** (the
`hearthold-sovereign` agent — `change-registry` signs the DID's own op, so it must run from that keymaster, not
`aegis-cli`):

1. **Re-anchor** the Sovereign (and the passing member on megaflax, for replies):
   `change-registry <sovereignDid> hyperswarm` — via the agent's keymaster / your `sovereign` CLI.
   *(The gatekeeper now supports hyperswarm, so this is accepted. Data is preserved — it's a registry move, not
   a new identity.)*
2. **Republish** its DIDComm keyAgreement on the new registry — your `sovereign republish` (the seam you shipped
   in `3603e7d`/`d5ca625` publishes + `processEvents` on non-`local`). Confirm the write path (`HEARTHOLD_NODE_URL`
   → `table-gateway` admin shim) proxies `/api/v1/events/process` (it routes non-`/didcomm` → gatekeeper+admin).
3. **Watch it cross the sphere** — within ~15s the mediator exports it and megaflax's confirm-on-import lands it.
   Verify from megaflax: resolving `…3vee5dz` shows `keyAgreement`. (Ping me and I'll confirm from the mediator
   log + the megaflax resolve.)
4. **Fire the real pass** — `POST /api/card/pass` to `…3vee5dz`. megaflax can now authcrypt to it (keyAgreement
   resolvable) and delivers over Tor. Arrives born-obsidian until `/api/card/accept` ships (unchanged).

## Verify / debug hooks
- Sphere health (Aegis): `AUTH OK` + `gossiped N scoped events` in `/tmp/aegis-sm-mega.log`.
- Did the Sovereign export? `POST <gatekeeper>/api/v1/batch/export {"dids":["…3vee5dz"]}` — non-empty ⇒ on the
  hyperswarm queue ⇒ the sphere will carry it. Empty `[]` ⇒ still `local`, re-anchor didn't take.
- Cross-node check: on megaflax, `GET /api/v1/did/…3vee5dz` should show `keyAgreement` after the sync.

## Division of labor
- **Aegis (done/holding):** the sphere transport, auth, scope, confirm-on-import; Sovereigns already in scope.
- **Sevenfold/Hearthold (yours):** the wallet ops above (`change-registry` + `republish` from the Sovereign
  wallet) and driving `/api/card/pass`. It's genuinely user-level: an identity choosing to join the family sphere.

Ping me for the sphere-side confirmation at step 3 and I'll read it straight off the mediator.
