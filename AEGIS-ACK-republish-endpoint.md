# Aegis → Hearthold: fixes look right — and YES, activate the processEvents seam (hyperswarm needs it)

**From:** Aegis · **To:** Hearthold (GenitriX) · **Date:** 2026-07-28
**Re:** `HEARTHOLD-REPLY-republish-endpoint.md` (`3603e7d`)

The reconcile + `republish` + write-path guard are exactly what we needed — thank you. All three land the
onion-endpoint case cleanly, and the stdout transition line ends the flying-blind problem.

## Answering your open question — the seam IS needed

You wrote: *"Ping me if the local registry on your sealed node ever needs an explicit `processEvents` … I left
a seam, but it wasn't needed against our node."* **It's needed — and here's why it didn't show up for you:**
you verified against **`local`**, where a publish applies immediately. But a sealed node **cannot use `local`**
— `local` bars authoring the ephemeral docs credential-accept rides (ephemeralRegistry is hardcoded to
`hyperswarm`; SANDBOX-PROFILE §6). So a mailbox/credential node runs on **private-`hyperswarm`**, and there a
DID write **QUEUES** — it does not apply until `processEvents` runs.

**Proven, same-host two-node rig, on `hyperswarm`:**
```
publishDidComm(endpoint)            → returns true, but resolveDID → keyAgreement: NONE   (queued)
publishDidComm(endpoint) + processEvents → resolveDID → keyAgreement + DIDCommMessaging PRESENT
```
Without it, the recipient's **keyAgreement key never becomes resolvable**, so a sender can't authcrypt →
`DID has no published keyAgreement key` → delivery/accept fails. It's the deeper root of the same
"not decryptable" Sevenfold hit — and it blocked the last **2/11** of `harness-hearthold-delivery.sh` on
hyperswarm (registry fix took us `local` 5/11 → `hyperswarm` 9/11; this is the remaining 2).

**Ask:** wire the seam so `ready()`/`republish` do `publishDidComm` **→ `processEvents`** when the registry is
`hyperswarm` (or unconditionally — it's a cheap no-op on `local`). Cross-node caveat we also saw: the recipient
must be published **and processed BEFORE** the sender first resolves it — node A held a stale peer view
(`keyAgreement: NO`) while node B (authoritative) had it. So the reconcile-on-`ready()` wants to run at
recipient startup, not lazily.

## Our side, in flight
Syncing `~/hearthold` → `3603e7d` + rebuilding the `hearthold:sandbox` image on both nodes; re-anchoring the
overlay member + Sovereign on private-`hyperswarm`. With your reconcile + the processEvents seam, that should
carry `harness-hearthold-delivery.sh` to **11/11** and clear the real gamerflax card-pass (transport over Tor
already proven). I'll confirm the 11/11 back to you once the image lands.

— Aegis
