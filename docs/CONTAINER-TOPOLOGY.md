# Aegis container topology — local-first multi-Gatekeeper profiles

Aegis provides the container **profiles** for the local-first deployment model; Hearthold designs
the **policy** that selects them (`~/hearthold/docs/DRAWBRIDGE-GROUNDING.md`, "The DMZ — verification
without republication"). This doc is the profiles, the new DMZ lifecycle + teardown proof, the
`/1.0/identifiers` read-path finding, the measurements, and the two-machine setup as it ran.

Keymaster addresses **one** Gatekeeper at a time (via `ARCHON_GATEKEEPER_URL`). The three categories
differ only by **what network layer the Gatekeeper's registry gets**:

| Profile | Registry / mediator | Topic | Propagates | Network need |
|---------|---------------------|-------|-----------|--------------|
| **PRIVATE** | `hyperswarm` mediator, **unique** per-node topic | `/aegis-private/<rand>` | nothing (peerless) | DHT egress |
| **SPHERE** | `hyperswarm` mediator, **shared** topic | `/aegis-sphere/<shared>` | only sphere members' DIDs | DHT egress |
| **DMZ** | **NO mediator** | — | **nothing** (structural) | HTTP egress only |

## 1. The three profiles

**PRIVATE / SPHERE** are env configurations of the base stack (`deploy/topology/{private,sphere}.env.example`):
they add the `hyperswarm` compose profile (runs `hyperswarm-mediator`) and put the Gatekeeper on the
`hyperswarm` registry so operations queue for the mediator. The **only** difference between them is
`ARCHON_PROTOCOL` — a **unique** random topic (PRIVATE, peerless by construction) vs a **shared** secret
topic (SPHERE, syncs with the members who set the same value). Mint PRIVATE topics per-install
(`openssl rand -hex 32`, via `setup-node.sh`); never ship a shared default (see the hyperswarm hardening
in `SANDBOX-PROFILE.md §7`).

**DMZ** is the new one: `deploy/topology/docker-compose.dmz.yml` — a Gatekeeper with **no** mediator.
Grounded (Hearthold, confirmed against source): `resolveDID` is pure DB read + local replay
(`gatekeeper.ts:682-728`), never touching the swarm; the `hyperswarm-mediator` is the **only** code path
from "operation in the DB" to "operation on the wire" (`hyperswarm-mediator.ts:355-419`). So a Gatekeeper
with that container simply absent can hold, resolve, and cryptographically verify imported operations with
**zero** capability to push them onward.

Verified live (mediator-less DMZ):

```
starts cleanly ........ ready=true, no mediator container in the stack
serves resolution ..... /api/v1/did/<did> returns the resolution triple
accepts import ........ POST /api/v1/dids/import -> {"queued":3} ; /events/process -> {"added":3}
                        then resolves the imported DID INDEPENDENTLY (verificationMethod present = verifiable)
propagates nothing .... /api/v1/registries -> ["local"]  (no hyperswarm registry => nothing ever queued;
                        the shareDb/relayMsg propagation path has no process to run)
```

**Coordination contract (Hearthold `DmzSession.assertPeerlessTarget`):** the DMZ profile's
`/api/v1/registries` returning **exactly `["local"]`** IS the target-isolation signal Hearthold's
`DmzSession.open` interrogates before importing — a mediator-less node can only anchor on non-propagating
registries, so `["local"]` is a direct, grounded signal (not a heuristic; needs no new Aegis field).
`docker-compose.dmz.yml` pins `ARCHON_GATEKEEPER_REGISTRIES=local` precisely to keep this true. Verified
live across the topology: DMZ, node B, and node A all return `["local"]` (accepted as peerless); a SPHERE
node returns `["local","hyperswarm"]` and is refused (`PeeredTargetError`). Any Aegis profile intended as a
DMZ target MUST keep the registry set `["local"]` — adding `hyperswarm` (even with the mediator stopped)
flips the signal to peered by design (fail-safe: refuse if propagation is *possible*, not just *live*).

## 2. DMZ lifecycle — ephemeral, destroyed on exit

Disk-backed (no in-memory engine needed); state lives in **named volumes** so teardown provably removes
everything. Egress note: the DMZ still needs **HTTP egress** to fetch a counterparty's `/dids/export` —
that is independent of gossip ("no gossip mediator ≠ no network"); it just has no mediator.

```bash
docker compose -p aegis-dmz -f deploy/topology/docker-compose.dmz.yml up -d      # spin up (localhost:4260)
docker compose -p aegis-dmz -f deploy/topology/docker-compose.dmz.yml down -v    # destroy
```

**Teardown proof (ran):** `down -v` → both named volumes (`aegis-dmz_dmz-redis`, `aegis-dmz_dmz-ipfs`)
**Removed**; no bind-mount residue (we use named volumes, not `./data-dmz`); a fresh `up` resolves the
previously-imported DID as **notFound** — no state survived. Nothing to garbage-collect, no stray IPFS repo.

## 3. The open read path — `/1.0/identifiers`

**Finding: it cannot be disabled at the application layer — there is no flag.** The Gatekeeper mounts it
**unconditionally** (`gatekeeper-api.ts:2246`, `app.use('/1.0/identifiers', createIdentifiersRouter(...))`),
and Drawbridge proxies it **verbatim and deliberately un-L402-gated** for universal-resolver interop
(`drawbridge-api.ts:768`, comment: "Intentionally open (no L402)"). Correct for a public node; a **leak**
for a PRIVATE or SPHERE one — anyone who can reach the HTTP port resolves any DID the node holds, unauth.

**Close it per-node at the deployment/network layer (documented options, strongest first):**
1. **Don't expose the port off-box.** Publish Gatekeeper/Drawbridge on `127.0.0.1` only (the DMZ profile
   does exactly this: `ports: ["127.0.0.1:4260:4224"]`) — or put the stack on an `internal: true` network
   (the SANDBOX/two-node profiles). The read path then exists but is unreachable from the LAN/public.
2. **Don't run Drawbridge.** Keymaster reaches the Gatekeeper on the internal Docker network by name; with
   no Drawbridge there is no public HTTP surface proxying `/1.0/identifiers` at all.
3. **Edge-filter the path.** A reverse proxy / firewall rule blocking `/1.0/identifiers` (and the
   `/api/v1/did/*` resolve routes) in front of a node that must publish *some* other endpoint.

**Archon-core ask (macterra):** add an env flag to disable `/1.0/identifiers` (or L402-gate it) per-node,
so a private/sphere node can keep an HTTP surface without the open resolver. Today it's network-layer only.

### Sealing the admin WRITE surface — `docker-compose.sealed.yml` (deployment layer)

The two-machine demo exposed a sharper hole than the read path: a raw `POST /api/v1/dids/import` (with a
known/shared admin key) writes foreign ops straight into the node's own DB. Hearthold's `PrivateGatekeeper`
type removes `importDIDs` — but that binds *Hearthold code*; the raw HTTP endpoint still sits below it, and
a `curl` (or a malicious peer) reaches it. **`gatekeeper-guard.mjs` + `docker-compose.sealed.yml` shut it at
the network edge**: the raw gatekeeper is unpublished (internal-only); a **resolution-only guard** takes the
`:4324` port and returns **403** for `/dids/import`, `/events/process`, DID enumeration (`POST /dids/`), and
bulk export (`/dids/export`, `/1.0/identifiers/<did>/data` — the content leak), while still forwarding the
GET reads a peer's fallback needs (`/api/v1/did/<did>`, `/1.0/identifiers/<did>`). Verified live: import/admin
→ 403 even *with* a valid admin key; gamerflax still resolves megaflax's DIDs through the guard.

```bash
# layer LAST; keep measure.yml as the first -f (project dir → deploy/topology, where the guard file sits):
... -f docker-compose.measure.yml -f docker-compose.sphere-tailnet.yml -f docker-compose.sealed.yml up -d
# GUARD_MODE=private (env) additionally blocks resolution — a node that serves no peer.
```

## 4. Measurements — cost tracks gossip exposure, not existence

Steady-state on megaflax (Docker Desktop, 7.6 GiB). Same node stack throughout; only the topic varies, so
the delta is attributable to gossip exposure.

| Config | Mediator | Gatekeeper | ipfs | redis | node total | DIDs held | Notes |
|--------|----------|-----------|------|-------|-----------|-----------|-------|
| **DMZ** (no mediator) | — | 71 MiB / 0.5% | 75 MiB / 2.3% | 6 MiB | **~152 MiB**, idle | 1 (imported) | disk ~144 KiB |
| **PRIVATE** (peerless) | 62 MiB / 0.3% | 63 MiB | 65 MiB | 5 MiB (+km 62) | **~260 MiB**, idle | ~1 | `mediator_active_connections 0` |
| **SPHERE** (few members) | ~62 MiB* | 71 MiB | 66 MiB | 7 MiB (+km 61) | **~270 MiB** | 3 | bounded gossip → stays near PRIVATE |
| **PUBLIC** (busy topic `/ARCHON/v0.8-beta`) | **121 MiB** / 0.4% | **229 MiB / 71–90% CPU** | 193 MiB / 30% | 10 MiB | CPU-**bound** | **4.8k → 18k+ climbing** | 2 peers, receiving the whole topic |

\* SPHERE mediator taken from the PRIVATE peerless figure — the measurement harness's mediator crashed on
the local-registry node-ID workaround (a harness artifact of breaking the mediator/keymaster confirm
deadlock, not a topology cost); the sphere *node* (gatekeeper+keymaster+ipfs+redis) measured healthy.

**Scaling curve (busy public topic, 2 peers):** DIDs held 4,810 → 8,219 → 13,049 → 18,376 in ~2 min, the
Gatekeeper pinned at 80–90% CPU replaying and verifying every gossiped operation, memory climbing with the
DB. Growth is bounded only by the topic's total DID population, not by this node's own activity.

**Verdict: HYPOTHESIS CONFIRMED.** Cost tracks **gossip exposure**, not existence. A mediator's mere
presence on a peerless/private topic is ~62 MiB, effectively idle (0.3% CPU). The expense appears only when
the topic delivers volume: the same mediator on an open public topic doubles, and — the real cost — the
**Gatekeeper** goes CPU-bound importing thousands of gossiped operations, memory and disk growing with them.
A SPHERE stays cheap precisely because its shared topic bounds the DID volume to its members. The
DMZ (no mediator) is the floor: it receives nothing, so it costs nothing beyond serving what you import.

**Image architecture caveat (found on gamerflax).** The `ghcr.io/archetech/*` images are published
**linux/arm64 only** (built on Apple Silicon). An **amd64/x86-64** peer (e.g. gamerflax) can't run them
natively — the gatekeeper exits 255. Two fixes: (a) **emulate** — `docker run --privileged --rm
tonistiigi/binfmt --install arm64`, then add `-f deploy/topology/docker-compose.emulate-arm64.yml` (forces
the three Node services onto arm64 under qemu; fine for validating the link, slower under load); or
(b) **build native** amd64 images from `~/archon` (`docker compose build gatekeeper keymaster
hyperswarm-mediator`, which tags them `ghcr.io/archetech/*` so the topology compose finds them). Worth
raising with macterra: publish multi-arch (arm64+amd64) images.

## 5. Two-machine setup — megaflax ↔ gamerflax (Tailscale)

**Plan (Tailscale over Hyperswarm NAT traversal).** Rather than fight Hyperswarm's DHT NAT traversal
through Docker's bridge — and, if gamerflax is Windows, WSL2's second translation layer — put the two
machines on a **Tailscale tailnet** and let the Gatekeepers reach each other over stable tailnet IPs. The
registry topic is still set (shared `ARCHON_PROTOCOL` for a two-member SPHERE); Tailscale just provides the
reliable transport the mediators peer over.

Steps (run on **each** machine):
1. Install Tailscale, `tailscale up`; note each host's `100.x.y.z` tailnet IP (`tailscale ip -4`).
2. Set the **same** `ARCHON_PROTOCOL=/aegis-sphere/<shared-hex>` on both (a two-member sphere).
3. Bring up the SPHERE profile on both (`private.env.example` base + the shared topic).
4. Cross-resolve check: point each node's `ARCHON_GATEKEEPER_FALLBACK_URL` at the peer's **tailnet**
   Gatekeeper (`http://100.x.y.z:4224`) so on-demand resolution works even before gossip converges — the
   same fallback mechanism as the `deploy/two-node/` peer profile, just over the tailnet instead of a shared
   Docker network.
5. On Windows/WSL2 gamerflax: run the stack **inside WSL2** and expose the Gatekeeper port to the Windows
   host (`netsh interface portproxy` or WSL2 mirrored networking) so the tailnet IP reaches it; publish
   Gatekeeper on the WSL2 interface, not `127.0.0.1`.

### What actually ran (live, both machines)

- **megaflax** — Apple Silicon macOS, tailnet `100.81.183.80`, `sphere-mega` node, gatekeeper published on
  `:4324`, fallback → `http://100.100.83.52:4324`.
- **gamerflax** — amd64 **Linux**, tailnet `100.100.83.52`, `sphere-gamer` node, gatekeeper `:4324`,
  fallback → `http://100.81.183.80:4324`. Both on the shared `/aegis-sphere/…` topic (`registries=["local",
  "hyperswarm"]`).

**Bidirectional cross-node resolution over the tailnet — CONFIRMED live:**
- gamerflax resolves megaflax's `alice` → its gatekeeper falls back to megaflax over the tailnet ✓
- megaflax resolves a gamerflax DID → its gatekeeper falls back to gamerflax over the tailnet ✓

The **fallback resolver over the tailnet is the reliable cross-node mechanism** (the same one proven on the
single-host two-node harness); the shared hyperswarm topic is set for gossip but the fallback is what makes
on-demand resolution deterministic. Each node stays its own isolated Gatekeeper — nothing bulk-syncs; a DID
resolves across the pair only when looked up.

**Setup notes from the actual run** (things that bit, so they're documented):
- **Tailscale on macOS sandboxes Taildrop from the CLI** — couldn't push files host-to-host that way.
- **The `ghcr.io/archetech/*` images are arm64-only.** gamerflax (amd64) either emulates
  (`tonistiigi/binfmt --install arm64` + `docker-compose.emulate-arm64.yml`) or builds native from
  `~/archon`. It ran under emulation here. → ask macterra for multi-arch images.
- **GHCR auth**: the archetech images are private; the amd64 peer needs `docker login ghcr.io` (PAT with
  `read:packages`) or a side-loaded image tarball.
- **Fresh Docker on Linux**: add the user to the `docker` group; run compose **without** `sudo` so the
  `ARCHON_*` env vars are honored.
- Publish the gatekeeper on `0.0.0.0:4324` (reachable on `tailscale0`); a host firewall may need
  `allow in on tailscale0 to any port 4324`. (WSL2 port-proxy note above applies only if the peer is
  Windows; gamerflax was native Linux, so no translation layer was needed.)

## 6. Private topic vs Sphere — and why active card-passing needs a mediator

§5's selective fallback is the right coupling for **arms-length** peers (resolve a DID on demand, nothing
bulk-syncs). But it has a hard limit, and crossing it is what distinguishes a *private node* from a *sphere*.

### The limit: fallback resolves CONFIRMED state only (the "gate 3" finding, 2026-07-28)

The peer fallback (and the `/1.0/identifiers` universal-resolver surface it uses) returns only the **confirmed**
DID document. On the `hyperswarm` registry **with no mediator**, a `create` event is auto-confirmed — so
provisioning and basic resolution work cross-node — but any **post-create UPDATE stays *unconfirmed***. The
load-bearing case is `publishDidComm`: an identity's **keyAgreement key** (needed to encrypt *to* it) and its
**DIDComm service endpoint** are updates. So:

> A sender on node A resolves a peer on node B, gets the *confirmed base* doc, and sees **no keyAgreement** —
> even though node B's own `/api/v1/did` shows it. `packDidComm` fails `DID has no published keyAgreement key`,
> and cross-node DIDComm / credential-accept never completes.

Proven live: node B `/api/v1/did` → `keyAgreement: YES`; node B `?confirm=true` and `/1.0/identifiers` → `NO`;
node A via fallback → `NO`. This is **not** registry (that gate is: use `hyperswarm` + `ARCHON_GATEKEEPER_REGISTRIES=local,hyperswarm`) and **not** an app bug — it's cross-node *confirmation* of updates.

### Private topic ≠ Sphere

- **Private topic** (`/aegis-private/<random>`) is a node's **solo isolation** — unique, local-only, nobody
  else on it. You never share it or run a mediator on it; doing so would defeat the isolation it exists for.
- **Sphere** (`/aegis-sphere/<random>`) is a **separate, deliberately-shared** topic for a defined member group,
  with a mediator that **distributes and confirms** members' operations to each other. The private topics stay
  private; the sphere sits alongside them as the group's confirmation domain.

Selective fallback = arms-length peers. **A sphere = members** who want to be mutually resolvable *including
updates* — which is exactly what two people **actively passing cards** are.

### The three gates for a cross-node card-pass (each with its owner)

| Gate | Owner | Fix |
|---|---|---|
| **1. Transport** — a sealed message physically reaches the other node | Aegis (L6) | Tor onion front (`ONION-MAILBOX.md`) or tailnet — **proven** |
| **2. Registry** — author the ephemeral/credential docs accept rides | Aegis (substrate) | `hyperswarm` registry + gatekeeper `local,hyperswarm` support (§ SANDBOX-PROFILE 6) |
| **3. Cross-node update confirmation** — sender sees the recipient's keyAgreement | **Sphere / mediator** | `aegis-secure-mediator` confirms the update cross-node |

### The mediator IS the sphere's confirmation mechanism — `aegis-secure-mediator` (`deploy/secure-mediator/`)

A hardened drop-in for Archon's stock `hyperswarm-mediator`, using Archon **as-is** (public gatekeeper/keymaster
HTTP API; no core changes). Four properties:

1. **Tailnet transport** — private `hyperdht` (`bootstrap`=a tailnet seed, `host`=own tailnet IP,
   `firewalled:false`): members connect **directly over WireGuard**. This is what fixes the stock mediator's
   `Connected nodes: 0` — the public-DHT holepunch fails between two NATs (see the gossip diagnosis).
2. **Peer auth** — a peer joins only by proving control of an **allowlisted member node DID** (`SM_MEMBERS`):
   challenge nonce → `keymaster /keys/sign` → `verifyProof` + allowlist + topic + fresh-nonce. The sphere is
   scoped to *exactly* the intended members — not open gossip.
3. **Scoped gossip** — only `SM_SHARE_DIDS` are exported out **and** accepted in; a member's private
   (local-registry) DIDs are structurally un-gossipable.
4. **Confirm-on-import (v0.2)** — after `/batch/import`, it calls `/events/process`, so a synced **update**
   actually applies to the resolvable doc. This is the change that closes **gate 3**: with it, a peer's
   keyAgreement/endpoint publish becomes resolvable across the sphere; without it the sync only relays
   already-confirmed state. (`/batch/import` alone returns `{queued:N, processed:0}` — the process step is
   mandatory on a queuing registry.)

**Isolation is preserved:** `internal:true` everywhere except the deliberate tailnet leg; no public DHT, no
public egress; membership + share-scope are cryptographically enforced. The sphere is a *private group channel*,
not exposure. This replaces the stock mediator image on the sphere nodes — mature it here, then propose upstream.
