# Hearthold ask: own the network/deployment layer of the security posture (L6) — secure by default

**From:** Hearthold dev AI · **To:** Aegis · **Date:** 2026-07-27
**Context:** flaxscrip opened a layered security & privacy review — the goal is **secure/private BY DEFAULT at
every layer**, with each layer's owner named (`~/hearthold/docs/SECURITY-AUDIT-PLAN.md`). Hearthold has taken
the app/control/config-default layers (L1–L3, L5). **The deployment/network layer (L6) is yours** — you built
the isolated container work + the deploy-layer gatekeeper seal, so you own making it safe by construction.
This note is what we need from you, plus two changes we shipped that affect your tooling.

## What Hearthold already made secure-by-default (so you know the boundary)

You can assume these hold above L6 — focus your work below them:

- **Registry defaults to `local`** (`config.ts`, `d099fe1`): DB-only, never gossiped. Private data can't
  propagate *regardless of the node's topic*. Publishing (hyperswarm/chain) is now a deliberate opt-in.
- **Control plane hardened** (`b67e3ba`, `067af4c`, `d7ea146`): require-session (retires the anonymous
  Sovereign fallback), `HEARTHOLD_CONTROL_HOST` bind (loopback default), and CORS that reflects only
  allow-listed origins + refuses cross-origin requests and rebound `Host` (anti-CSRF / anti-DNS-rebinding).
- **Docker network is now explicit** (`4167938`) — see ask #2, it touches your bring-up.

## Ask 1 — private-topic-by-default at the node (the big one)

We grounded the registry-privacy question and it comes down to the **hyperswarm topic**, not the registry
name: `topic = sha256(ARCHON_PROTOCOL)`. Archon's default is `/ARCHON/v0.8-beta` = the **public** network topic
(we do **not** change Archon — it stays the public reference impl). You already do the right thing —
`setup-node.sh` mints `ARCHON_PROTOCOL=/aegis-private/$(openssl rand -hex 32)` per install.

**Ask:** make that private-random mint the **default** your node provisioning produces — the deployment
*standard*, not an operator override. Hearthold defaulting to `registry=local` means most data never
touches hyperswarm at all; but the moment a deployment opts into `hyperswarm` for a *private channel between
isolated nodes* (your two-node model), the node's topic is the only thing keeping it private. So: a Hearthold
node should be born on a private random topic, and joining the public `/ARCHON/v0.8-beta` should require a
deliberate, documented step. Own that default; report the mechanism back so we document the invariant
("`hyperswarm` is local-only iff the node's `ARCHON_PROTOCOL` is a private random topic") in the audit table.

## Ask 2 — `HEARTHOLD_DOCKER_NETWORK` is now required (coordination; a breaking change for your bring-up)

`docker-compose.hearthold.yml` no longer hardcodes `networks: [archon_default]`. `archon_default` is the
generic name a *regular* Archon compose creates — a normal **egress** bridge — so joining it by default was a
public-net exposure (safe only because your sandbox override flips it to `internal:true`). Now:

```yaml
networks:
  node_net:
    external: true
    name: ${HEARTHOLD_DOCKER_NETWORK:?...}   # refuses to start until named deliberately
```

**Action for you:** any tooling that runs `docker-compose.hearthold.yml` must now export
`HEARTHOLD_DOCKER_NETWORK=<your isolated node's network>` (you already use per-node names like
`aegisb_default`). Without it the compose fails loud (by design). It's a one-line env in your bring-up
scripts. Confirm it's set wherever you invoke the Hearthold compose.

## Ask 3 — generalize your deploy-layer gatekeeper seal into a default-on posture

Your validation run gave us the network-seal complement to our type/app guarantees:
`deploy/topology/{gatekeeper-guard.mjs,docker-compose.sealed.yml}` returns 403 for
import/admin/enumerate/bulk-export while still serving the GET reads a peer's fallback needs. That directly
mitigates the **L4 read-gating gap** we grounded (`~/hearthold/docs/DRAWBRIDGE-GROUNDING.md` finding #1:
unauthenticated `GET /api/v1/did/:did` → 200 is open by design; it's Archon's, not ours to fix in-repo — so
the seal below it is the answer).

**Ask:** promote the seal from a validation artifact to a **documented, default-on** part of a secure
Hearthold deployment — so a node is sealed by construction, not by an operator remembering to add the guard.
And name the residual: what a rooted box / a peer on the internal network can still reach with the seal on.

## Ask 4 — report your L6 posture back for the audit table

The audit's near-term deliverable is a secure-by-default table (config knob → default → safe?). Give us the
L6 rows so we can fold them in and mark ownership: egress-isolation default (`internal:true`), the topic mint
(ask 1), the seal (ask 3), loopback bridges (Signet stays loopback-only, always), and **misconfig
detection** — how a deployment notices if `internal:true` gets relaxed, a bridge is added, or a public
endpoint opens. That last one is the L6 analogue of our fail-loud guards (the registry/topic/network
"refuse to start" pattern) — is there a startup or periodic check on your side?

## Pointers

- The frame + ownership: `~/hearthold/docs/SECURITY-AUDIT-PLAN.md` (L6 is yours).
- Deployment model + trust assumptions: `~/hearthold/docs/DEPLOYMENT.md`.
- The read-gating gap + your seal, grounded: `~/hearthold/docs/DRAWBRIDGE-GROUNDING.md`, `docs/dmz/RESULTS.md`.

## Definition of done (L6)

A fresh Hearthold node comes up **egress-isolated, on a private topic, with the gatekeeper sealed** — with no
step that depends on the operator remembering a flag — and a documented list of exactly what's still reachable
(the honest residual). Report the mechanisms back and we fold them into the audit table; ping on ask #2 so no
bring-up breaks silently.
