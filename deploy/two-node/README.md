# Connecting two isolated Aegis nodes

Aegis defaults to **fully isolated** — `internal: true`, no route to the public
internet at all (SANDBOX-PROFILE.md §3). That's the right default: you test the
whole stack locally, in a sealed sandbox, before you trust it. This directory is
the **opt-in next step**: connecting your isolated node to *one trusted friend's*
isolated node — while **still cut off from the public internet**.

> **The isolation guarantee is preserved.** "Opening up to a friend" does not open
> you to the world. The peer link is a shared network that is *also* `internal:
> true`, so the two nodes see each other but neither can reach the internet —
> verified: after connecting, both gatekeepers still `ENETUNREACH` on a dial to a
> public IP.

## What connects two nodes

Archon separates DID **creation** (local, on each node) from **resolution**. The
hinge is the gatekeeper's **fallback resolver** (`ARCHON_GATEKEEPER_FALLBACK_URL`
— which the isolated profile deliberately leaves blank). Archon's gatekeeper
implements the universal-resolver `/1.0/identifiers/<did>` convention, so **one
node's fallback can point at another node's gatekeeper**. When node A needs a DID
it doesn't hold (e.g. one created on node B), it forwards the resolution to node
B, which returns the full resolved document. Point them at each other (A→B, B→A)
and DIDs resolve across the pair — no public DHT, no hyperswarm, no shared
registry. DIDs stay on their home node; resolution travels.

### Fallback resolver modes: peer (private) vs. public (SaaS) vs. chained

`ARCHON_GATEKEEPER_FALLBACK_URL` is a general **read-only resolver** hook, and it has more
than one useful target. The local gatekeeper always stays the **authority for the Sovereign's
own (private) DIDs** — creation and updates never leave the box. The fallback only *reads*
DIDs the node doesn't hold. That opens three modes:

| Mode | Fallback points at | Enables | Isolation |
|------|--------------------|---------|-----------|
| **Peer** (this guide) | a trusted friend's gatekeeper | resolve each other's private DIDs | full — `internal:true`, no public egress |
| **Public** | a public **SaaS gatekeeper** (Bitcoin + other registries) | opt-in "public DID resolution" — resolve DIDs anchored on public networks (a bank's DID, a DID you migrated to Bitcoin) | **scoped** — the gatekeeper needs egress to *that one resolver host*, nothing else |
| **Chained** | peer, whose *own* fallback → public | both at once, hop by hop | peer stays private; only the outermost hop is public |

The **public** mode is the clean way to give a Sovereign optional public reach **without
de-isolating their node**: private DID management stays local and offline; a separate,
read-only public gatekeeper answers "what is *this* DID on Bitcoin?" It's the natural
complement to DID **migration** — once you move a years-old private DID onto Bitcoin, a
public fallback is what lets anyone (including your future self) resolve it.

Tradeoffs to design around: (1) it's egress, so it belongs on a **scoped** path (a bridge
sidecar or firewall rule to the resolver host only), not a blanket `internal:false`; (2) a
public resolver **sees which DIDs you look up** — a metadata/privacy leak the Sovereign opts
into knowingly; (3) Archon core currently supports **one** fallback URL, so true "peer *and*
public" needs either the peer to chain onward or a core enhancement to accept a fallback
**list**. Worth raising with macterra alongside the fallback-capable-`verifyOperation` ask.

### The regtest / `local`-registry caveat

Everything here is on the `local` registry (and, for Lightning, regtest). That
means **DIDs are node-local and ephemeral — nothing is permanently registered on
any public network.** Cross-node resolution works *live*, while both nodes are up
and linked. That's exactly what you want for "test locally, then open to a
friend": no permanent global footprint. Joining the *public* network (permanent
registration on a real registry) is a separate, later step — deliberately out of
scope here.

## Resolution carries public docs, NOT encrypted content (and how to pass a card)

Cross-node **resolution** (the fallback) returns only the W3C DID Resolution
triple — `didDocument` + metadata (`identifiers-router.ts:72-76`). It **omits
`didDocumentData`**, where Archon keeps an asset's *encrypted* payload (a VC's
ciphertext, an encrypted message). That's exposed separately at
`/1.0/identifiers/{did}/data`, which the fallback client does **not** fetch. So:

- **Public, on-demand:** resolving an identity, verifying a signature, reading a
  public DID document — all work across the peer via resolution alone. ✅
- **Private content does NOT leak over the peer:** an encrypted VC that lives on
  node A cannot be pulled+decrypted by node B from its DID alone — the ciphertext
  never crosses. `accept-credential <peer-did>` fails with `did not encrypted`.
  This is a *feature*: the peer link discloses public identity, never private
  content in bulk.

**To pass an encrypted card between nodes**, transfer its *content* explicitly
with the gatekeeper admin export/import (`scripts/admin-cli.js`, present in the
`cli` containers). Order matters — import the **controller (issuer) DID first**,
then the asset, because imported ops **defer** until their controller resolves
locally (`gatekeeper.ts:1126-1130`):

```bash
adminA(){ docker exec aegis-cli-1     node scripts/admin-cli.js "$@"; }
adminB(){ docker exec aegisb-cli-b-1   node scripts/admin-cli.js "$@"; }

adminA export-did "$ISSUER" > share/issuer.json     # 1. controller FIRST
adminA export-did "$SCHEMA" > share/schema.json     # 2. schema (if used)
adminA export-did "$VC"     > share/vc.json          # 3. the card
adminB import-did /app/share/issuer.json
adminB import-did /app/share/schema.json
adminB import-did /app/share/vc.json
adminB process-events        # applies queued ops (added:N, pending:0 when done)
# now the VC resolves LOCALLY on node B with its ciphertext → accept-credential works
```

(In production the natural transport for this is **DIDComm** — it packs the
encrypted card into a message and delivers it over the LAN — same idea, no manual
export.) `local` here means propagation is **selective**: you move exactly the
DIDs you choose. If instead you want assets to *auto*-propagate between two nodes,
put agents **and** assets on the `hyperswarm` registry and run a mediator on your
shared private `ARCHON_PROTOCOL` topic (§ Security below) — that's ambient bulk
sync between deliberate peers. Note the constraint: a `local` agent cannot anchor
a `hyperswarm` asset (its controller wouldn't resolve for hyperswarm peers), so
agent and asset registries must be compatible.

## Passing a card over DIDComm (the native transport)

Manual export/import is a sneakernet. The real transport is **DIDComm** — an
encrypted, authenticated message delivered node-to-node over the peer link. Wired
up here and validated end to end (`pass-card-didcomm.sh`).

Wiring (already in `docker-compose.peer.yml`): node A's **didcomm** service joins
`aegis-peer` (it makes the outbound delivery POST) and has
`ARCHON_DIDCOMM_ALLOW_PRIVATE_EGRESS=true` (to POST to a private/LAN host over
http — still no public internet). Each side publishes a reachable mailbox:

```bash
clib publish-didcomm http://drawbridge-b:4222/didcomm   # recipient (Bob)
clia publish-didcomm http://drawbridge:4222/didcomm     # sender (needed for authcrypt)
```

The published `DIDCommMessaging` service lives in the DID **document**, so it
crosses the peer via ordinary resolution. Delivery path:
`send-didcomm` → sender's own drawbridge `/didcomm/api/v1/deliver` → sender's
didcomm service POSTs to `http://drawbridge-b:4222/didcomm/api/v1/messages` →
recipient runs `receive-didcomm` to fetch + unpack.

**DIDComm does not auto-import the credential asset.** `receiveDidComm` only
unpacks the message; the native auto-accept path (`searchNotices`) runs over the
*registry*, which doesn't cross `local` nodes. So the message carries the **card
bundle** — issuer + schema + VC ops — and the recipient imports it, then accepts:

```bash
deploy/two-node/pass-card-didcomm.sh <sender-id> <recipient-DID> <vc-DID> [recipient-id]
```

### Two lessons this surfaced (offline-first divergence + the chatty protocol)

The first cross-node DIDComm send silently failed (`receive-didcomm` returned
`[]`). Root cause: Bob had **imported Ada's Agent DID earlier**, and Ada later ran
`publish-didcomm` (adding her key-agreement key). Bob's **stale local copy shadowed
the peer**, so he never saw Ada's new key → authcrypt unpack failed (and
`receiveDidComm` swallows unpack errors, `keymaster.ts:2794`). Re-syncing Ada's
newer ops fixed it — the exact offline-first reconciliation problem: an imported
copy of a **mutable** identity goes stale the moment its owner updates it while
disconnected.

The fix is a **rule about what to cache**:

| DID kind | Mutable? | Strategy |
|----------|----------|----------|
| **Agent** (identity/issuer) | yes — keys rotate, services get added | **Never import. Resolve fresh over the peer each exchange** (the "chatty protocol" — a little network chatter, never stale). |
| **Asset** (a VC) | no — issued once | Transfer the content once; caching is safe. |

Had Ada never been imported, Bob's `receiveDidComm` would have resolved her
**fresh** via the peer fallback and unpacked on the first try. Fresh resolution is
*already* how keymaster-level operations (unpack, verify, resolve) work — they go
through the HTTP resolve path, which is fallback-capable.

**The one gap:** importing a VC still needs its issuer resolvable by the **core**
gatekeeper (`verifyOperation` → local-only `resolveDID`, `gatekeeper.ts:460`). The
peer fallback (`resolveFromUniversalResolver`) is a **server-layer** wrapper the
core never calls — so an asset import currently requires the issuer *locally
present*, which is the only reason the bundle ships the issuer at all. Making the
core verify path fallback-capable (and honoring `versionTime`, which the current
fallback drops) would let a node import-and-verify an asset against a
freshly-resolved issuer it never has to cache. Worth raising with Archon core.

## Where this lives: Aegis vs. Hearthold

Aegis is the **egress-isolated deployment** of Hearthold, not the app. So:
- **Archon core** owns the DIDComm primitives (`send/receive/pack/unpack`, notices).
- **Aegis** (this repo) owns the isolated **transport substrate** — the peer
  network, `ALLOW_PRIVATE_EGRESS`, and thin scripts that exec into the isolated
  containers (`pass-card-didcomm.sh`, the roleplay wrappers).
- **Hearthold / Sevenfold** should own the card-passing **protocol** (bundle shape,
  send/accept semantics, the cache rule above) as a portable feature that works on
  *any* Archon deployment — isolated or public. `pass-card-didcomm.sh` is a
  transport **demo/validation**, not the home for that protocol.

## Validate it on ONE host first (what this dir does)

Before wiring two physical machines, prove the whole thing on a single host by
running a second, self-contained node (node B) beside your normal node (node A).
The connection *logic* is identical to the two-machine case; only the transport
differs (a shared internal Docker network here vs. a LAN link there).

```bash
# from the archon repo root, with node A already up:
cp deploy/two-node/nodeb.env.example deploy/two-node/nodeb.env   # then set the two secrets
docker network create --internal aegis-peer                      # the shared, internal peer link

# bring up node B (its own data dir ./data-nodeb, ports 52xx, no Mongo/Lightning):
docker compose -p aegisb --env-file deploy/two-node/nodeb.env \
  -f deploy/two-node/docker-compose.nodeb.yml up -d

# put node A into "peer mode" (opt-in overlay: joins aegis-peer + fallback -> node B):
docker compose --env-file .env \
  -f docker-compose.yml -f docker-compose.override.yml -f docker-compose.lightning-zap.yml \
  -f deploy/two-node/docker-compose.peer.yml up -d gatekeeper
```

Node B's `nodeb.env` sets `NODEB_FALLBACK_URL=http://gatekeeper:4224` (→ node A on
the peer net); node A's peer overlay sets its fallback → `http://gatekeeper-b:4224`.

### Prove it

```bash
# create an identity on node B:
docker exec aegisb-cli-b-1 node scripts/archon-cli.js create-wallet
BOB=$(docker exec aegisb-cli-b-1 node scripts/archon-cli.js create-id bob | grep -oE 'did:cid:[a-z0-9]+')

# node A resolves it — via the peer fallback (fails before peer mode, succeeds after):
./archon resolve-did "$BOB"

# isolation still holds on both, even connected:
docker exec aegis-gatekeeper-1 node -e 'require("http").get({host:"1.1.1.1",port:80,timeout:5000},()=>{}).on("error",e=>console.log(e.code))'  # ENETUNREACH
```

## Security: two peering models — resolution (safe) vs. hyperswarm (bulk)

There are two very different ways two Archon nodes can share DIDs, and the
difference matters a lot on a friend's LAN:

- **Fallback resolution (what this guide uses):** *on-demand, one DID at a time.*
  Node A asks node B to resolve a specific DID when it needs it. Nothing is
  bulk-copied; you disclose only what you look up. This is the safe, deliberate
  model.
- **Hyperswarm (bulk gossip):** *replicates your ENTIRE DID database* to any peer
  it discovers on its **topic**. The topic is derived (`sha256`) from
  `ARCHON_PROTOCOL`, whose upstream default — `/ARCHON/v0.8-beta` — is **shared by
  every Archon node in existence**. On a shared LAN, mDNS/local discovery doesn't
  even need the public DHT: two nodes on that default topic would silently
  replicate everything to each other.

**Hardening (built into install):** the Aegis profile sets `ARCHON_PROTOCOL` to a
**unique random topic** instead of the shared default, so hyperswarm bulk-sync is
**opt-in** — it only happens between nodes that *deliberately* set the same value
(a private swarm between trusted friends), never by accident.

This is **not a value we ship** — a hardcoded "random" topic committed to the repo
is not random: every install that copied it would share it, recreating the exact
footgun. Instead each node **mints its own** at setup time. `deploy/setup-node.sh`
does this as step one of standing up a node (alongside a unique admin key and
wallet passphrase — same reasoning: no shared secrets across installs):

```bash
deploy/setup-node.sh          # generates .env with a fresh /aegis-private/<random> topic
                              # (do it by hand if you must: openssl rand -hex 32)
```

(Hyperswarm is off in the isolated profile anyway, so this is defense-in-depth —
but it's exactly the kind of default you want hardened *before* a laptop full of
private history joins someone else's network. Because it's generated per install,
the default is *safe by construction*: two Aegis nodes never share a topic unless
their operators choose to.)

## Going to a real second machine (same LAN)

The only thing that changes is the *transport* of the peer link. Instead of a
shared internal Docker network on one host, node B runs on the friend's machine
(e.g. `gamerflax`) and each node reaches the other over the LAN by published port:

- Node B publishes its gatekeeper on its LAN IP (already mapped to host `:5224`).
- Node A's fallback becomes `PEER_GATEKEEPER_URL=http://<gamerflax-lan-ip>:5224`
  (and node B's `NODEB_FALLBACK_URL=http://<megaflax-lan-ip>:4224`).
- To keep app containers off the public internet while reaching the LAN peer, run
  the peer link through a bridge sidecar (a container that straddles the node's
  `internal: true` network and a LAN-facing network, relaying only the gatekeeper/
  drawbridge/didcomm ports) — or scope host firewall rules to the peer. The
  resolution + DIDComm *mechanism* is unchanged; only where the fallback points.

## Files

| File | Purpose |
|------|---------|
| `docker-compose.nodeb.yml` | Node B: a second, minimal Aegis node (redis/ipfs/gatekeeper/keymaster/drawbridge/didcomm/cli), own data dir + ports + internal net, joined to `aegis-peer`. |
| `docker-compose.peer.yml` | Node A "peer mode" opt-in overlay: join `aegis-peer` + fallback → node B. Omit it and node A is fully isolated again. |
| `nodeb.env(.example)` | Node B's config (secrets gitignored). |
