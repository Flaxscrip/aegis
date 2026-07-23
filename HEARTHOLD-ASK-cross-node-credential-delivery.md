# Hearthold ask: cross-node credential delivery over DIDComm

**From:** Aegis (the egress-isolated deployment of Hearthold)
**Goal:** let a Hearthold agent deliver a verifiable credential to a subject agent
on a **different node that does not share a registry**, and have the subject accept
(and optionally KB-ingest) it — over DIDComm, working on any deployment.

This is deployment-agnostic Hearthold protocol logic. Aegis only provides the
isolated transport substrate; it has a throwaway proof-of-concept
(`deploy/two-node/pass-card-didcomm.sh`) that this brief generalizes. **No "card"
terminology and no isolation awareness in Hearthold — speak "credential".**

## Where it goes
`~/hearthold/packages/core/src/` — build on `transport.ts` (`DidCommTransport`:
`ready`/`request`/`serve`, authcrypt, thread-correlated) and extend `credentials.ts`
(or add `credential-delivery.ts`).

## The problem, precisely
`credentials.ts:acceptCredential` calls `keymaster.acceptCredential(did)`, which
`lookupDID`s the credential — fine when issuer + subject **share a registry**. Across
isolated nodes it fails, for two structural reasons we verified live:

1. **Cross-node resolution carries only the public W3C DID document, never the
   encrypted `didDocumentData`** (Archon `identifiers-router.ts:72` omits it by
   design). So a subject cannot pull + decrypt a VC from the issuer's node by DID
   reference alone — `accept-credential` → `did not encrypted`. The VC **content**
   must travel in the message.
2. **DIDComm does not auto-accept credentials.** `receiveDidComm` only unpacks; the
   native auto-accept (`searchNotices`) runs over the *registry*, which doesn't cross
   isolated nodes. So the receiver needs explicit glue: recognize a credential-
   delivery message → make the VC resolvable locally → `acceptCredential`.

## What to build

### Sender: `deliverCredential(transport, toDid, credentialDid)`
- Package what the subject needs to make the VC locally resolvable + verifiable:
  the **VC asset ops** and its **schema ops** (both immutable — safe to ship).
  Get them via the gatekeeper admin export (`exportDIDs([did])`).
- Send as a `HearthholdMessage` over `DidCommTransport.request/serve` (authcrypt
  already authenticates the issuer at the transport layer).

### Receiver: a `RequestHandler` for credential-delivery messages
- Import the shipped ops into the local gatekeeper (`importDIDs` + `processEvents`),
  then `acceptCredential(credentialDid)`; optionally run the existing VC→KB bridge
  (`ingestCredentialToPartition`) into the subject's partition.

### The cache rule (important — offline-first correctness)
- **Do NOT ship or import the issuer's Agent DID.** Identities are **mutable** (keys
  rotate, services get added); an imported copy goes **stale** the moment the issuer
  updates while disconnected. We hit this live: a stale imported issuer lacked its
  new key-agreement key → authcrypt unpack **silently** failed (`keymaster.ts:2794`
  swallows unpack errors). **Resolve the issuer FRESH over the peer every time** (the
  "chatty protocol"). Only cache **immutable** assets (the VC, its schema).

## Known blocker to escalate to Archon core (macterra), not to work around
Importing the VC still needs its **issuer** resolvable by the **core** gatekeeper.
`verifyOperation` uses core, **local-only** `resolveDID` (`gatekeeper.ts:460`); the
peer fallback (`resolveFromUniversalResolver`) is a **server-layer** wrapper the core
never calls, and it also drops `versionTime`. So an asset import currently requires
the issuer **locally present** — the only reason a naive implementation would ship
the issuer at all (violating the cache rule).
**Ask for core:** make `verifyOperation`'s controller resolution fallback-capable and
`versionTime`-honoring, so a node can import + verify an asset against a
freshly-resolved issuer it never has to cache. Until then, if you must ship the issuer
for import, treat it as a **refreshable throwaway**, never authoritative — re-resolve
fresh for any signature/authcrypt use.

## Also worth a fix
`keymaster` `use-id <name>` prints `Unknown ID` but **exits 0** — a typo'd identity
silently proceeds as whatever is current. Guard by checking `listIds` first.

## Definition of done
On two nodes with **no shared registry** (only mutual DID resolution), issuer agent A
delivers a VC to subject agent B over DIDComm; B accepts it, and verification resolves
A's issuer DID **fresh** (A never imported/cached on B). Works identically on a shared-
registry deployment (where it can short-circuit to the native notice path).

**Executable acceptance test (already exists):** `deploy/two-node/pass-card-didcomm.sh`
proves the transport, and `deploy/two-node/harness-credential-exchange.sh` is the
acceptance harness in Hearthold's vocabulary (issuer agent / subject agent / credential —
10 assertions incl. isolation + the divergence check). Its PHASE 4 has a marked seam:
replace the `pass-card-didcomm.sh` call with Hearthold's `deliverCredential(...)` and the
harness should still pass 10/10.

## Environment (where to test)
The isolated two-node substrate is live: `~/isolation/aegis` on this host. Node A containers
are `aegis-*` (project `aegis`), node B is `aegisb-*`, both on the internal `aegis-peer`
network with mutual fallback resolution and no public egress. The Hearthold agent containers
(`hearthold-*`) already run on node A's `archon_default` network. Run the harness from
`~/isolation/aegis`. (Aegis owns this substrate; you build in `~/hearthold`.)
