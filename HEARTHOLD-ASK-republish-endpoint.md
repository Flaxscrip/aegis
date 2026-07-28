# Hearthold ask: a way to (re)publish an identity's DIDComm endpoint after the fact

**From:** Aegis · **To:** Hearthold · **Date:** 2026-07-28
**Context:** We stood up a **Tor onion mailbox** in front of the Drawbridge (sealed node, no inbound port —
`deploy/topology/ONION-MAILBOX.md`). The transport is **proven**: a sealed DIDComm message from one laptop
lands in another's mailbox over Tor (`POST http://<onion>:4222/didcomm/api/v1/messages` → 400 "not a real
envelope" = reached). For a *sender* to auto-discover that route, the recipient's Sovereign DID must
**advertise** `serviceEndpoint = http://<onion>:4222/didcomm`. We could not make it do so — and it lands in
your layer.

## What blocks it (two findings)

1. **Publishing is a DID *write*, so it needs the admin/write path — not the mailbox front.** A member that
   points `HEARTHOLD_NODE_URL` at a *resolve-only* front (our mailbox-only Drawbridge fronts `/api/v1/*`
   resolve + `/didcomm`, but deliberately does **not** proxy gatekeeper writes / inject an admin key) cannot
   author the DID update. The republish must go through the admin write path (for us, the `table-gateway`
   admin shim). Worth a guard/log in Hearthold: "publishDidComm failed — NODE_URL cannot write."

2. **`transport.ready()` never re-publishes.** In `packages/core/src/transport.ts`, `ready()` does
   `if (await this.hasEndpoint(endpoint)) return;` and otherwise `publishDidComm(endpoint, idName)`. On our
   node the Sovereign kept advertising a **stale** `http://didcomm:4236` even after we set
   `HEARTHOLD_DIDCOMM_ENDPOINT` to the onion and pointed the write path at `table-gateway`. The republish
   neither fired nor surfaced — the agent logs to a **file**, so `docker logs` is empty and we're flying
   blind. Net: once an endpoint is published, we found **no supported way to change it**.

## The ask

Expose a **supported way to (re)publish an identity's DIDComm service endpoint** — one of:
- a small control/CLI command, e.g. `hearthold republish-didcomm --id <name> --endpoint <uri>`, that does
  `unpublishDidComm(name)` → `publishDidComm(uri, name)` (and `processEvents` if the local registry needs it
  to apply), OR
- make `ready()` **reconcile**: if the currently-advertised DIDComm endpoint differs from the desired one,
  re-publish it (not just publish-if-absent), and **log the outcome to stdout** (success/failure + reason).

Either lets an operator point a member/Sovereign at a new reachable endpoint (an onion, a tailnet address, a
migrated host) after first boot — which is exactly what "open the mailbox on Tor" needs.

## Same root cause blocks credential ACCEPT — found while validating Sevenfold's registry fix

Re-running `harness-hearthold-delivery.sh` on `hyperswarm` (the registry fix), the last 2/11 still failed at
`acceptCredential` with: **`DID has no published keyAgreement key; call publishDidComm first`**. Root-caused it
to the *same* publish flow, and it's a concrete, fixable ordering bug:

- **`publishDidComm` on `hyperswarm` QUEUES the DID update — it does not apply until `processEvents` runs.**
  `transport.ready()` calls `publishDidComm` but never `processEvents`, so the identity's **keyAgreement key
  never lands** in its resolvable DID doc. Proven: after `publishDidComm` **then** `processEvents`, the
  keyAgreement key + `DIDCommMessaging` service both appear; before, `keyAgreement: NONE`.
- Consequence: a sender resolving the recipient finds **no keyAgreement** → cannot authcrypt → delivery/accept
  fails. This is exactly Sevenfold's "not resolvable/decryptable," one level deeper.
- **Cross-node amplifier:** the recipient must be published+processed **before** the sender first resolves it —
  we saw node A hold a **stale** peer-fallback view (`keyAgreement: NO`) while node B (authoritative) had it.

**The concrete fix (folds into the ask above):** make `ready()` do `publishDidComm` **→ `processEvents`** (so
the key actually lands), reconcile-if-changed (not publish-if-absent), and **log the outcome to stdout**. Same
one change unblocks: (a) advertising an onion endpoint, and (b) credential accept between two nodes.

## Not blocking the demo
The transport is proven, so a sender can deliver to the **known** onion directly meanwhile. This ask is what
makes it *self-describing* (resolve the DID → get the onion → deliver) instead of out-of-band.
