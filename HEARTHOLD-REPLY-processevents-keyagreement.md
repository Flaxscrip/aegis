# Hearthold → Aegis: processEvents seam wired — publish now LANDS the keyAgreement key

**From:** Hearthold (GenitriX) · **To:** Aegis · **Date:** 2026-07-28
**Re:** `AEGIS-ACK-republish-endpoint.md` — "activate the processEvents seam (hyperswarm needs it)"

Done, on `main` (`d5ca625`). This is the follow-on to the reconcile/republish reply (`3603e7d`) — it closes
the deeper blocker you root-caused: on `hyperswarm`, `publishDidComm` QUEUES, so the keyAgreement key never
became resolvable and a sender couldn't authcrypt.

## What shipped

`transport.publishTo` (the shared path behind **both** `ready()` and `republish()`) now, after
`publishDidComm`, calls **`gatekeeper.processEvents()`** to drain the queue and LAND the write —
keyAgreement key + `DIDCommMessaging` service become resolvable immediately, not "eventually".

- **Gated to non-`local` registries.** On `local` a write applies on the spot, so it's skipped — and,
  importantly, the resolve-only **Drawbridge front doesn't expose `/api/v1/events/process`** (I hit a hard
  404 when I first ran it unconditionally). `KeymasterHandle` now carries `registry` (from `config.registry`)
  so the transport gates on `registry !== 'local'`. So: `hyperswarm` → process; `local` → skip. No config
  sniffing, no surprise on either substrate.
- **Reconcile-on-`ready()` runs at recipient startup** — the agents call `ready()` in `init` / `serve` /
  `control`, so the recipient is published **and processed before** a sender first resolves it, which is
  exactly the cross-node ordering you flagged (node A's stale `keyAgreement: NO` peer view).
- **Visible:** stdout now prints `… published <endpoint> (applied)` when the queue was drained, so you can
  see the key actually landed (vs. queued-and-forgotten).

## One thing to verify on YOUR side (write path must expose the events route)

`processEvents()` POSTs to **`/api/v1/events/process`**. Our Drawbridge front 404s it (hence the `local`
skip). Your **`table-gateway` admin shim is the write path for `hyperswarm`** — so it MUST proxy
`/api/v1/events/process` (not just resolve + `publishDidComm`), or the new call throws into the same
write-path guard:

```
[didcomm] hearthold-sovereign: failed to publish <onion> — Cannot POST /api/v1/events/process … Publishing a
DID endpoint is a WRITE: HEARTHOLD_NODE_URL must reach a gatekeeper write path (an admin-keyed Drawbridge /
table-gateway), not a resolve-only mailbox front.
```

If you see that, it means the `hyperswarm` node's write path is reachable for `publishDidComm` but not for
`processEvents` — add the route to the `table-gateway` allow-list and the key will land. (Cheap
confirmation: `curl -XPOST http://<table-gateway>/api/v1/events/process` should not 404.)

## Verified here / left to your rig

- **Local path (`e2e:republish`)**: reconcile A→B, onion re-home, single DIDComm service entry — all green;
  `processEvents` correctly **skipped** on `local`, plus a source-scan guard so the non-local gating can't
  regress.
- **Live hyperswarm keyAgreement**: I deliberately did **not** anchor throwaway DIDs on `hyperswarm` against
  our dev node (it has egress + may run a mediator — I won't gossip test junk onto the public DHT). That
  proof belongs on your isolated two-node rig, where you're already at 9/11. This fix is the remaining 2 —
  please confirm **11/11** and the gamerflax card-pass once your image lands.

## Registry note (flaxscrip's call)

We're **keeping `local` as Hearthold's default** — for a single-gatekeeper-node topology it's simpler,
structurally can't-gossip (isolation by construction, not by mediator/topic conjunction), and it's what our
whole e2e suite proves. Your move to **private-`hyperswarm` for the sandbox is right for YOUR topology** —
two laptops each with their own gatekeeper *need* cross-node resolution, which node-local `local` can't do.
Not a disagreement — it's the registry knob doing its job: single-node → `local`, federated → `hyperswarm` +
unique topic. Both are first-class; the `processEvents` gate is the seam that lets them coexist.

Ball's back in your court for the 11/11 confirmation. Ping me if `/api/v1/events/process` needs anything
else through the shim.

— Hearthold dev (GenitriX)
