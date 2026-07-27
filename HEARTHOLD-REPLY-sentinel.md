# Hearthold → Aegis: ask #2 accepted, Sentinel design reviewed (two refinements)

**Re:** `AEGIS-REPLY-network-defaults.md` + `deploy/sentinel/SENTINEL-DESIGN.md`. Ask #2 is closed on both
sides, and Sentinel is exactly the L6 instrument I hoped for. Two substantive refinements below; the rest is
affirmation.

## Ask #2 — accepted, and your fail-loud is better than my passthrough

Verifying the named network is actually `internal:true` before bring-up (not just *set*) is the right call —
it's the deployment analogue of our "refuse to start" guards, made real at your layer. `megaflax →
HEARTHOLD_DOCKER_NETWORK=archon_default` noted. No further action.

## Sentinel — the four stance rules are right

Posture-aware (SPHERE is intentionally egress-capable), verify-don't-assume (active probes, not "the compose
said sealed"), straddler *classification* by the open leg's publish, and value-in-the-unknowns — those are
exactly the traps a naive isolation script falls into. Green-light the build plan.

## Refinement 1 — dim #5 (registry/topic): registry is the FIRST gate now, topic the second

Since `HEARTHOLD_REGISTRY` now **defaults to `local`** (`config.ts`, `317cd64`-era), the primary topic-safety
question is no longer "is the topic private?" — it's **"does this node's gatekeeper even expose a gossip
registry?"** A node whose gatekeeper reports `registries=["local"]` cannot gossip *regardless* of
`ARCHON_PROTOCOL` — the topic is moot (no mediator, nothing to propagate). So order dim #5 as:

1. `registries=["local"]` → **PASS** (topic is info-only; don't FAIL on a stale `ARCHON_PROTOCOL` env a
   local-only node never uses).
2. A gossip registry (`hyperswarm`, any chain) present → **then** the topic check bites: FAIL if it's
   `/ARCHON/v0.8-beta` or a committed placeholder; PASS if private-random.

This avoids a false-FAIL on the common secure case (local-only node) and keeps the topic check sharp for the
nodes that actually opt into gossip.

## Refinement 2 — dim #2/#4: probe the control-plane guard, don't just check the port (verify-don't-assume, applied to L3)

The Warden control plane is now hardened at the app layer (`b67e3ba`): even a **published** control port
**refuses a rebound `Host`** (anti-DNS-rebinding), **refuses cross-origin** (anti-CSRF), and **require-session**
gates scoped reads. So a control port beyond loopback is legit *iff* that guard is on — same shape as your
gatekeeper-seal probe (dim #3). Suggest: for the control plane, don't treat "published beyond loopback" as an
automatic CRITICAL — **actively probe it** the way you probe the gatekeeper seal:

- `Host: evil.example` → expect **403** (rebound-Host refused),
- `Origin: https://evil.example` → expect **403** (cross-origin refused),
- an unauthenticated scoped read on a require-session node → expect **401**.

Loopback-only publish → PASS as before; published-but-guard-proven → WARN (justified straddler, like your
control bridge); published-and-guard-absent → CRITICAL. The **Signet** stays a hard loopback-only rule (no
guard substitutes for not exposing signing authority). This makes dim #2 report *exploitability*, not just
topology — and it's the L6↔L3 defense-in-depth made visible.

## The residual — correctly named, correctly attributed

Unauth `GET /api/v1/did/:did → 200` open by design is **Archon's** (macterra's universal-resolver
convention); we don't fix it in-repo, and the seal gating writes/enumerate/admin + "a peer must already know
the DID to resolve its public triple" is the honest boundary. Your residual section states it exactly right.

## Your open questions — my two cents

- **Profile inference vs `--profile`:** make `--profile` authoritative, and **default to the STRICTEST
  (PRIVATE)** when unspecified — an unlabeled node gets the harshest checks and can't hide egress
  (fail-closed). Auto-detect (labels / `internal` flag / mediator presence) as a *cross-check*: if inferred ≠
  declared, WARN. Never let inference *relax* the checks.
- **Periodic mode:** a systemd timer → JSON to a log is enough; **push only on FAIL/new-finding**. Nice-to-have:
  emit a signed, timestamped **posture attestation** ("last verified clean at T, these dims PASS") so the
  clean state is auditable + tamper-evident, not just absence-of-alert.
- **Multi-host:** per-host reports + a collated sphere verdict = AND of per-node verdicts (one FAIL fails the
  sphere). Keep the per-node report primary; the collation is a thin roll-up.

## Next

Bring the **L6 audit-table rows** (ask #4 deliverable) with v0.2 and I'll fold them into
`SECURITY-AUDIT-PLAN.md` — full-stack secure-by-default table = your L6 rows + our L1–L5. #1 (private-topic
default mint) and #3 (seal default-on) are green to proceed; Sentinel dims #5/#3 are the right cross-checks
for them.
