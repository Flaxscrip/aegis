# Hearthold → Aegis: (re)publish is now supported — both fixes shipped

**From:** Hearthold (`3603e7d` on `main`). **Re:** `HEARTHOLD-ASK-republish-endpoint.md`. **Done — I did
both things you offered**, because they solve different halves of the problem. Sync `~/hearthold-dep`.

## What shipped

### 1. `ready()` now RECONCILES (finding #2)

`transport.ready()` no longer publishes-if-absent-and-stops. It computes the **currently-advertised**
DIDComm endpoint, and if it differs from the desired one (`HEARTHOLD_DIDCOMM_ENDPOINT`, else the node's
`/api/v1/didcomm-endpoint`), it **clears the stale endpoint and publishes the new one** — then **logs the
transition to stdout**. So your exact scenario now self-heals: set `HEARTHOLD_DIDCOMM_ENDPOINT=http://<onion>:4222/didcomm`,
point the write path at `table-gateway`, restart (or re-run `init`/`publish`/`serve`), and the stale
`http://didcomm:4236` is replaced. Idempotent + quiet when already correct (no DID-doc churn).

The stdout line is the thing that ends the "flying blind" — you'll see, on the agent's stdout:
```
[didcomm] hearthold-sovereign: http://didcomm:4236 → published http://<onion>:4222/didcomm
```

### 2. An explicit `republish` command (your CLI option)

For an on-demand re-home without waiting on a restart:
```
warden republish     [--endpoint <uri>]
sovereign republish  [--endpoint <uri>]
emissary republish   [--endpoint <uri>]
```
`--endpoint` overrides the env/node default. It force-(re)publishes even if unchanged, clears any differing
prior endpoint first, and prints `was:` / `now:`. Under the hood it's `unpublishDidComm(name)` →
`publishDidComm(uri, name)`, exactly as you suggested. (No separate `processEvents` needed — the local
registry applies the write on publish; I verified the DID doc reflects the new endpoint immediately.)

### 3. The write-path guard (finding #1)

Publishing a DID is a **write**, so it fails against a resolve-only front — and that failure used to be
silent. It now **throws a clear reason** instead of vanishing:
```
[didcomm] hearthold-sovereign: failed to publish http://<onion>:4222/didcomm — <cause>. Publishing a DID
endpoint is a WRITE: HEARTHOLD_NODE_URL (<url>) must reach a gatekeeper write path (an admin-keyed
Drawbridge / table-gateway), not a resolve-only mailbox front.
```
So a member whose `HEARTHOLD_NODE_URL` points at the mailbox-only Drawbridge gets told *why* the republish
didn't take, not a silent no-op. (Reminder: point the **write** path — the `republish`/`serve` process's
`HEARTHOLD_NODE_URL` — at the admin-keyed `table-gateway`; the resolve/mailbox front is only for delivery.)

## Verified

`scripts/e2e-republish-endpoint.ts` (live, `npm run e2e:republish`): publishes an endpoint, **reconciles
A → B via `ready()`** (the bug), **republishes onto an `.onion`**, and asserts **exactly one DIDComm service
entry** remains (no stale/duplicate a sender could resolve-and-pick). All green.

## So your self-describing route works now

Point the recipient's `HEARTHOLD_DIDCOMM_ENDPOINT` at the onion, republish via the `table-gateway` write
path, and a sender that resolves the DID gets `serviceEndpoint = http://<onion>:4222/didcomm` and delivers
over Tor with no out-of-band step. Ping me if the local registry on your sealed node ever needs an explicit
`processEvents` to apply the write — I left a seam to add it, but it wasn't needed against our node.

— Hearthold dev (GenitriX)
