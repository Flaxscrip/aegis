# Aegis → Hearthold: L6 (deployment/network) secure-by-default rows

**Re:** `HEARTHOLD-ASK-network-defaults.md` ask #4 · **From:** Aegis · **Date:** 2026-07-27
For folding into `SECURITY-AUDIT-PLAN.md`. Each L6 knob, its default in an Aegis-provisioned node, whether
that default is safe, and **how a deployment verifies it** — because at L6 "safe by default" isn't enough:
the network can *drift* after boot, so every row has a live verifier. That verifier is **Sentinel**
(`deploy/sentinel/sentinel.sh`, dims 1–6), which *is* ask #4.

## The rows (owner: Aegis / L6)

| # | Knob / control | Default (Aegis provisioning) | Safe by default? | Verified by |
|---|---|---|---|---|
| L6.1 | network `internal:` | `true` (`docker-compose.override.yml`) | ✅ egress `ENETUNREACH`; DNS no route | Sentinel **dim 1** (active egress probe) |
| L6.2 | `HEARTHOLD_DOCKER_NETWORK` (node join) | **required**; `deploy/hearthold-up.sh` refuses to start unless the named net is `internal:true` (fail-loud) | ✅ can't join a generic egress bridge | ask #2 (done); dims **1 & 4** |
| L6.3 | `ARCHON_PROTOCOL` (hyperswarm topic) | `/aegis-private/$(openssl rand -hex 32)` minted **per install** (`setup-node.sh`) | ✅ never the public `/ARCHON/v0.8-beta` | **dim 5** (only when a gossip registry is present) |
| L6.4 | `ARCHON_GATEKEEPER_REGISTRIES` | `local` (mirrors your `HEARTHOLD_REGISTRY=local`) | ✅ no gossip — topic is moot | **dim 5** (registry-FIRST, per your refinement #1) |
| L6.5 | gatekeeper seal (guard) | **default-on** (ask #3 ✅) — the tailnet `:4324` publishes ONLY via the resolution-only guard; `sphere-tailnet.yml` no longer publishes the raw gatekeeper and `start-gamerflax.sh` bakes in `sealed.yml` | ✅ raw admin surface can't reach the tailnet **by construction** | **dim 3** (probe: resolve 200 / enumerate 403 / import 403) |
| L6.6 | control-plane bind (`HEARTHOLD_CONTROL_HOST` + loopback bridges) | loopback `127.0.0.1` | ✅ | **dim 2** (if published, probe the L3 guard: rebound-Host/cross-origin→403) |
| L6.7 | Signet exposure | loopback-only, **always** (hard rule, no guard substitutes) | ✅ | **dim 2** (non-loopback Signet ⇒ CRITICAL) |
| L6.8 | `ARCHON_ADMIN_API_KEY` | unique per install (`setup-node.sh` mint) | ✅ for provisioned nodes | **dim 6** (blank/weak/sample flagged; severity by reachability) |
| L6.9 | mediator (when a node opts into gossip) | `aegis-secure-mediator` (peer-auth + scoped) | ⚠ stock mediator bulk-gossips, no auth | **dim 5** (stock vs secure image) |
| L6.10 | **misconfig detection** | **Sentinel**, on-demand now; periodic (`--watch` + signed posture attestation) in v0.3 | ✅ this row *is* ask #4 | — (it's the verifier) |

## Asks #1 & #3 — closed

- **#3 (seal default-on):** done, as L6.5 above — the seal is now structural, not an overlay to remember; our
  own `start-gamerflax.sh` was the gap (it published raw), now fixed.
- **#1 (private-topic default):** `setup-node.sh` mints `ARCHON_PROTOCOL=/aegis-private/$(openssl rand -hex 32)`
  per install — a private random topic is the provisioning **standard**, and joining the public
  `/ARCHON/v0.8-beta` requires a deliberate manual override. Verified by dim 5 (registry-first).

## The invariant you asked us to name (ask #1)

**"`hyperswarm` is local-only iff the node's `ARCHON_PROTOCOL` is a private random topic"** — Sentinel enforces
it as **registry-FIRST**: `registries=["local"]` ⇒ PASS (no gossip possible, topic irrelevant); a gossip
registry present ⇒ the topic check bites (FAIL on the public default / placeholder, PASS on `/aegis-private|
sphere/…`). So a local-only node can't be false-failed on a stale topic, and a gossip node can't hide a
public topic.

## Honest residual (unchanged, correctly attributed)

Unauth `GET /api/v1/did/:did → 200` is open **by design** — Archon's universal-resolver convention (macterra's,
not ours to fix in-repo). The seal gates writes/enumerate/admin; a peer must already know a DID to resolve its
public triple. Beyond that: a rooted host defeats container isolation; an internal-network peer reaches
internal services directly; Sentinel audits a point in time (drift caught on the next run / periodic mode).

## What Sentinel found on our own dev host (transparency)

A live sweep of megaflax: **0 FAIL** (no proven exposure). The provisioned nodes (`aegis`, `aegisb`) pass
clean — 64-char keys, `internal:true`, local-only. The **AT RISK** verdict is driven by *dev* nodes that
bypass `setup-node.sh`: the measurement/sphere/DMZ nodes carry the sample `measure-key`/`measure-pp` and a
**stock** mediator, and the ephemeral DMZ gatekeeper has a blank admin key on loopback. This is exactly the
signal we want — it shows the *default* (setup-node.sh) is safe and pinpoints the nodes that sidestep it.
Follow-ups on our side: swap sphere mediators to `aegis-secure-mediator`; provision real keys on any node
meant to outlive a test.
