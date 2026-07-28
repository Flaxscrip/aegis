# aegis-secure-mediator

A hardened replacement for Archon's stock `hyperswarm-mediator`, for spheres whose nodes sit behind
**different NATs** and are linked by **Tailscale**. It uses **Archon as-is** — every gatekeeper/keymaster
call is the public HTTP API (`@didcid/*` surface). No archon core changes; swap it in for the stock
mediator image. Goal: mature it, then propose upstream.

## Why

The stock mediator is `new Hyperswarm()` with no config: it relies on the public DHT + UDP holepunch,
which **does not traverse two different NATs** (proven on megaflax↔gamerflax), and it re-creates its swarm
(new keypair) every 60s while unconnected — a cold-start deadlock. It also gossips **`getDIDs()` = the entire
node** to **anyone who knows the topic**.

## What this changes (4 properties)

1. **Tailnet transport** — private `hyperdht` (`bootstrap`=a seed on the tailnet, `host`=own tailnet IP,
   `firewalled:false`). Nodes connect **directly over WireGuard**; no public DHT, no holepunch, stable (no churn).
2. **Peer authentication** — a peer joins only by proving control of an **allowlisted member node DID**:
   challenge nonce → `keymaster /keys/sign` (addProof, key stays in the keymaster) → peer runs
   `keymaster /keys/verify` + checks the signer DID ∈ `SM_MEMBERS` + the nonce is the fresh one it issued.
   Knowing the topic is **not** enough.
3. **Scoped gossip** — only `SM_SHARE_DIDS` are exported out **and** accepted in. Everything else is dropped,
   so a member's private (local-registry) DIDs are **structurally un-gossipable** — the non-pollution
   guarantee enforced at the transport layer.
4. **Confirm-on-import (v0.2)** — after `POST /batch/import`, it calls `POST /events/process`. `/batch/import`
   only **queues** ops (`{queued:N, processed:0}`); on the `hyperswarm` (queuing) registry they apply to the
   *resolvable* DID doc only after processing. Without this, a peer's post-create **update** — its
   `keyAgreement` key / DIDComm endpoint — never becomes resolvable here, so the sphere would relay only
   already-confirmed state and cross-node DIDComm/credential-accept would still fail ("gate 3"). *With* it, the
   member group actually **confirms** each other's updates. Proven: import → `{queued:2,processed:0}`; process
   → `{added:2}` → `keyAgreement` resolves. See `docs/CONTAINER-TOPOLOGY.md §6`.

## Trust model / setup

To join a sphere, members exchange **out of band** (same as sharing the topic): the sphere protocol string,
the seed address, and each other's **node DIDs**. Each member imports the other member DIDs locally (so
`/keys/verify` can resolve the signer offline) and lists them in `SM_MEMBERS`. `SM_SHARE_DIDS` is the set of
DIDs that node publishes to the sphere.

## Config (env)

| var | meaning |
|-----|---------|
| `SM_GATEKEEPER_URL` / `SM_KEYMASTER_URL` | RAW gatekeeper/keymaster (not the guarded port — batch import is admin-gated) |
| `SM_ADMIN_KEY` | gatekeeper+keymaster admin key |
| `SM_NODE_NAME` | this node's keymaster id whose DID signs the handshake |
| `SM_PROTOCOL` | shared sphere string → `sha256` → topic |
| `SM_SEED` | `host:port` of the hyperdht seed (on the tailnet) |
| `SM_BIND` | this node's tailnet IP (needed for `firewalled:false`) |
| `SM_MEMBERS` | comma-sep allowlist of member node DIDs (auth) |
| `SM_SHARE_DIDS` | comma-sep DIDs allowed to cross (scope) |

## Run

```bash
docker build -t aegis-secure-mediator:latest deploy/secure-mediator

# 1) the seed, on the stable node (megaflax), bound to its tailnet IP:
docker run -d --name aegis-seed --network host aegis-secure-mediator:latest \
  node seed.mjs 49737 100.81.183.80

# 2) the mediator, on each member node (host-networked; point at the RAW gatekeeper/keymaster):
docker compose -f deploy/secure-mediator/docker-compose.secure-mediator.yml up -d secure-mediator
```

Because it's host-networked, it reaches the node's gatekeeper/keymaster either via their container bridge IP
or a loopback-published port (the guarded `:4324` won't work — the guard blocks `/batch/*` and `/dids/import`).

## Status

v0.2 — transport + peer-auth + scoped-gossip + **confirm-on-import** (the gate-3 fix — `/events/process` after
`/batch/import`), against the public Archon API. Validated by hand-simulating one sync
(export→import→process) between the two isolated nodes: the recipient's `keyAgreement` became resolvable on the
sender's node and DIDComm delivery advanced past encryption. **Next (live deployment):** stand up the tailnet
`seed` between megaflax↔gamerflax and run the mediator on both aegis/Hearthold nodes, scoped to the Sovereign +
overlay-member DIDs — then re-run the delivery end-to-end over Tor. Further maturation: bind the mediator
identity to the node DID via a signed cert; per-DID publish policy; metrics; local `processEvents` before export
so a just-published local update is exported already-applied.
