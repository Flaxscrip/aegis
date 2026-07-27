# Sentinel — design capture

**Status:** **v0.1 BUILT** (`sentinel.sh`, dims 1–4, validated live on megaflax: 23 PASS · 9 WARN · 0 FAIL);
design reviewed + green-lit by Hearthold (`HEARTHOLD-REPLY-sentinel.md`) · **Owner:** Aegis (L6) ·
**Captured:** 2026-07-27
**Purpose:** a security-posture auditor for an Aegis/Hearthold **deployment** — it *identifies and tests*
whether a node/sphere is actually isolated and hardened as intended, on demand, and catches drift.

Sentinel is the **L6 (deployment/network) instrument** of the layered security review
(`~/hearthold/docs/SECURITY-AUDIT-PLAN.md`). Hearthold owns L1–L5 (app / control / config defaults);
we own L6. It is specifically the answer to **Hearthold ask #4 — "misconfig detection"**: the L6 analogue of
Hearthold's fail-loud guards (registry/topic/network "refuse to start"). Where they fail *loud at startup*,
Sentinel proves the posture *from the outside, any time* — because a network can drift after boot (a port
opened, `internal:true` relaxed, a bridge added) in ways a startup check never sees again.

We have been *claiming* egress-isolation and non-pollution throughout this project. Sentinel is the tool that
**proves** those claims on a running deployment and reports the honest residual.

---

## Stance (the design principles, learned from a live recon of megaflax)

A naive "is it isolated?" script is worse than useless. The 2026-07-27 recon taught four rules Sentinel must
embody:

1. **Posture-aware, not blanket.** A **SPHERE** node is *intentionally* egress-capable (it needs the
   hyperswarm DHT); a **PRIVATE** node must not egress. A blanket "egress = breach" probe false-positived on
   `sphere-mega` during recon. Sentinel reads the node's **declared profile** (PRIVATE / SPHERE / DMZ /
   CONTROL) and checks the invariants *for that profile*.
2. **Verify, don't assume.** A gatekeeper published on `0.0.0.0:4324` is safe **iff** the guard blocks
   admin/import/enumerate. Sentinel *actively probes* that every run (recon confirmed `resolve=200 ·
   enumerate=403 · import=403`) rather than trusting the compose file said "sealed".
3. **Straddlers need classification, not a boolean.** A container on `internal + non-internal` is a leak
   **only if** its open leg carries real egress or a non-loopback publish. The control-plane tcp-forward
   bridge legitimately straddles (`archon_default` + `console-lan`) but its open leg only publishes
   `127.0.0.1:4310` — fine. Naive detection both false-negatives and false-positives here.
4. **The value is in the unknowns.** Sentinel earns its keep by catching what the operator didn't intend — a
   stray `0.0.0.0` publish, a straddler with real egress, a **stock** (bulk-gossip, no-auth) mediator on a
   shared topic, a blank/sample admin key, or the **global default** hyperswarm topic `/ARCHON/v0.8-beta`.

**Operational stance:** read-mostly · safe to run against a live node · *adversarial* (tries to break
isolation and reports success as a finding) · never mutates · PASS / FAIL / WARN per check with **severity +
evidence + remediation**.

---

## Live baseline (megaflax, 2026-07-27) — the "known-good" reference

| Check | Result |
|---|---|
| Private node (`archon_default`, `internal:true`) egress | `ENETUNREACH` ✓ PASS |
| Guard on `0.0.0.0:4324` | resolve `200` · enumerate `403` · import `403` ✓ PASS |
| Control plane / Signet publish | `127.0.0.1:4310` / `127.0.0.1:4311` (loopback-only) ✓ PASS |
| Straddler audit | one straddler (control bridge) — open leg publishes loopback only ✓ OK |

This is the shape of a clean report and the fixture Sentinel's own tests should assert against.

---

## Dimensions (the check catalog)

| # | Dimension | Method | Fail = |
|---|---|---|---|
| 1 | **Egress isolation** | active outbound (no-DNS to a public IP) + DNS probe from each PRIVATE/DMZ container → must fail; SPHERE nodes reported egress-capable (info, not fail) | a private container reaches the internet |
| 2 | **Attack surface** (exploitability, not topology) | enumerate published ports; loopback-only → PASS. Published beyond loopback → **actively probe the guard** (verify-don't-assume, applied to L3): control plane → `Host: evil`→403, `Origin: https://evil`→403, unauth scoped read→401; gatekeeper → dim #3. Guard-proven ⇒ **WARN** (justified straddler); guard-absent ⇒ **CRITICAL**. **Signet = HARD loopback-only** (no guard substitutes for not exposing signing authority). | a published control/admin port with the guard absent |
| 3 | **Guard / seal** (ask #3) | actively probe any published gatekeeper: `resolve 200 / enumerate 403 / import 403 / admin 403 / /data 403` | a published gatekeeper answers admin/import/enumerate |
| 4 | **Straddler audit** | containers on internal+non-internal, **classified by the open leg's published ports** (loopback-only = OK, real egress / non-loopback = CRITICAL) | a straddler with real egress or a LAN publish |
| 5 | **Registry & topic** (ask #1) | **registry-FIRST** (registry defaults to `local`): gatekeeper `registries=["local"]` ⇒ **PASS**, topic is info-only — do *not* FAIL on a stale `ARCHON_PROTOCOL` a local-only node never uses. Only if a gossip registry (`hyperswarm`/chain) is present does the **topic check bite**: FAIL on `/ARCHON/v0.8-beta` or a committed placeholder, PASS on private-random. Plus **stock vs secure** mediator. | a gossip-enabled node on a public/shared topic; stock bulk-gossip mediator |
| 6 | **Secrets & endpoints** | admin key set & not a sample/default (`measure-key`, sample.env values); passphrase set; published DIDComm endpoint in-network (not a non-resolving external dummy, not leaking a real host) | blank/sample secret; leaked or broken endpoint |

**Optional / later:** non-pollution assertion (sovereign store is structurally local-only ⇒ un-pollutable;
no exposed importer path) — mostly subsumed by #3 + #5.

---

## Mapping to Hearthold's L6 asks (`HEARTHOLD-ASK-network-defaults.md`)

- **Ask 1 (private-topic-by-default):** Sentinel dimension **#5** *verifies* the invariant
  ("`hyperswarm` is local-only iff `ARCHON_PROTOCOL` is a private random topic"). The **default mint** itself
  is a `setup-node.sh` change (already mints `/aegis-private/$(openssl rand -hex 32)`) — Sentinel is the
  cross-check that a given node actually honored it.
- **Ask 3 (seal default-on + name the residual):** Sentinel dimension **#3** proves the seal live; the
  design's "honest residual" section (below) is the named residual.
- **Ask 4 (misconfig detection):** Sentinel *is* this — run on demand, and optionally as a periodic check.
- **Ask 2 (`HEARTHOLD_DOCKER_NETWORK` now required):** not a Sentinel item — a **bring-up coordination
  action** (export the isolated network name wherever we invoke `docker-compose.hearthold.yml`). Tracked
  separately; flagged because it can break the gamerflax Table bring-up.

---

## The honest residual (what the seal + isolation do NOT stop)

Name it, don't hide it (ask #3):

- **Unauthenticated `GET /api/v1/did/:did` → 200** is open *by design* (Archon's universal-resolver
  convention; `DRAWBRIDGE-GROUNDING.md` finding #1). The seal gates writes/enumerate/admin, not single reads
  a peer's fallback needs. A LAN/tailnet peer that already knows a DID can resolve its public triple.
- **A rooted host** (root on the box) defeats container isolation entirely — Sentinel audits *configuration*,
  not a compromised kernel.
- **A peer already on the internal network** can reach internal services directly — isolation is a perimeter,
  not per-service authn.
- Sentinel checks a **point in time**; drift between runs is only caught on the next run (hence the periodic
  mode in v0.3).

---

## Output & form

- **Terminal report** grouped by dimension — each check `PASS / FAIL / WARN` + severity
  (`critical / high / medium / info`) + evidence + one-line fix; a summary posture verdict. Same PASS/FAIL
  house style as `deploy/two-node/` harnesses.
- **`--json`** mode for records / CI / the audit table.
- **Form:** `deploy/sentinel/sentinel.sh` + small node helpers for the active HTTP probes. Runs on the node
  host (docker access). Read-only `docker inspect` + bounded active probes (egress attempt, guard probe).
  Takes `--profile private|sphere|dmz|control` (or infers from labels/networks/env).

---

## Boundary with Hearthold (so the two audits compose, no overlap)

- **Sentinel = L6 / Aegis:** network isolation, published ports, gatekeeper guard, registry/topic, deployment
  secrets & endpoints.
- **Hearthold = L1–L5:** session scoping, step-up reveal, key custody, CORS/CSRF, config defaults, credential
  flows. Sentinel's report ends with a **handoff block** listing the L1–L5 invariants it does *not* cover, so
  a full posture = Sentinel (L6) + Hearthold's own review.

---

## Build plan

- **v0.1** ✅ **BUILT** (`deploy/sentinel/sentinel.sh`) — dims 1–4; posture-aware sweep (infer per network,
  strictest default) + `--network`/`--profile`; active egress/seal/control-guard probes; grouped report +
  verdict + `--json` stub. Validated live on megaflax. **Refinement found in build:** unsealed-gatekeeper
  severity is **reachability-scoped** — loopback-only ⇒ WARN (e.g. the DMZ import path), non-loopback ⇒
  CRITICAL. (Same principle as dim #2's exploitability-not-topology.)
- **v0.2** — dimensions 5–6 (registry/topic, secrets/endpoints) + the L6 audit-table rows for Hearthold.
- **v0.3** — `--json`, posture score, periodic/`--watch` mode (the drift catcher), Hearthold handoff block.

## Resolved (Hearthold review, `HEARTHOLD-REPLY-sentinel.md`, 2026-07-27)

- **Profile:** `--profile` is **authoritative**; when unspecified, **default to the STRICTEST (PRIVATE)** —
  an unlabeled node gets the harshest checks and can't hide egress (fail-closed). Auto-detect (labels /
  `internal` flag / mediator presence) is a **cross-check only**: if inferred ≠ declared → **WARN**. Inference
  never *relaxes* a check.
- **Periodic mode:** a **systemd timer → JSON to a log** is enough; **push only on FAIL / new finding**.
  Nice-to-have: emit a **signed, timestamped posture attestation** ("last verified clean at T; dims … PASS")
  so the clean state is auditable + tamper-evident, not just absence-of-alert.
- **Multi-host:** **per-host reports + a collated sphere verdict = AND of per-node verdicts** (one FAIL fails
  the sphere). The per-node report stays primary; the collation is a thin roll-up.
