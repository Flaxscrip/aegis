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

### The regtest / `local`-registry caveat

Everything here is on the `local` registry (and, for Lightning, regtest). That
means **DIDs are node-local and ephemeral — nothing is permanently registered on
any public network.** Cross-node resolution works *live*, while both nodes are up
and linked. That's exactly what you want for "test locally, then open to a
friend": no permanent global footprint. Joining the *public* network (permanent
registration on a real registry) is a separate, later step — deliberately out of
scope here.

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
docker exec archon-gatekeeper-1 node -e 'require("http").get({host:"1.1.1.1",port:80,timeout:5000},()=>{}).on("error",e=>console.log(e.code))'  # ENETUNREACH
```

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
