# Aegis L6 posture report — megaflax

**Tool:** Sentinel v0.3 (`deploy/sentinel/sentinel.sh`) · **Layer:** L6 (deployment/network) ·
**Generated:** 2026-07-27T19:59:58Z · **For:** Hearthold (fold into `SECURITY-AUDIT-PLAN.md`)

Read-only audit of the running megaflax deployment (freshly rebuilt from committed config). Sentinel proves
the L6 invariants live — egress isolation, gatekeeper seal, control-plane guard, straddler classification,
registry/topic, secrets — and rolls up a verdict + a FAIL-weighted score. Verdict semantics: **OK** (nothing
above info) · **REVIEW** (medium/low WARNs) · **AT RISK** (a high-severity WARN or any FAIL) · **CRITICAL**.

## Verdict

**35 PASS · 27 WARN · 0 FAIL · score 61/100 → AT RISK**

**No proven exposures (0 FAIL).** The AT RISK is driven entirely by *dev-grade* settings on the
measurement/sphere/DMZ study nodes — the sample `measure-key`/`measure-pp` and the stock (bulk-gossip)
mediator — plus the ephemeral DMZ gatekeeper's blank admin key on loopback. The **provisioned** nodes
(`aegis`, `aegisb`) are clean: egress-isolated, 64-char keys, local-only registry. Follow-ups on our side:
swap the sphere mediators to `aegis-secure-mediator`; give any long-lived node a real key.

## Signed posture attestation (tamper-evident)

A compact, HMAC-signed record of this posture — the clean state is *provable*, not just "no alert fired".

**Human-readable view:**
```json
{
  "host": "megaflax.local",
  "timestamp": "2026-07-27T20:07:20Z",
  "sentinel": "v0.3",
  "verdict": "AT RISK",
  "score": 61,
  "summary": {
    "pass": 35,
    "warn": 27,
    "fail": 0
  },
  "findings_digest": "sha256:31c09a13a1ff76079e0c9b6a4a4706de60cbc81f45e2a1d212bdee3c7afd17e6"
}
```

**The signed bytes** — this exact one-line string is what the HMAC covers (`findings_digest` is SHA-256 over every finding line):
```
{"host":"megaflax.local","timestamp":"2026-07-27T20:07:20Z","sentinel":"v0.3","verdict":"AT RISK","score":61,"summary":{"pass":35,"warn":27,"fail":0},"findings_digest":"sha256:31c09a13a1ff76079e0c9b6a4a4706de60cbc81f45e2a1d212bdee3c7afd17e6"}
```

**Signature** (HMAC-SHA256): `dd592360b8cea603ac093e4bd08a635539bdcadcec1eda6e24198099ea86cd4b`

**Verify** (shared key, distributed out of band — here `megaflax-posture-2026`):
```sh
printf '%s' '{"host":"megaflax.local","timestamp":"2026-07-27T20:07:20Z","sentinel":"v0.3","verdict":"AT RISK","score":61,"summary":{"pass":35,"warn":27,"fail":0},"findings_digest":"sha256:31c09a13a1ff76079e0c9b6a4a4706de60cbc81f45e2a1d212bdee3c7afd17e6"}' | openssl dgst -sha256 -hmac 'megaflax-posture-2026' | awk '{print $NF}'
# → must equal the signature above
```

## Full findings

```
════════════════════════════════════════════════════════════════
 SENTINEL v0.3 — Aegis L6 posture audit   megaflax.local
════════════════════════════════════════════════════════════════

══════════════════════════════════════════════════════════════
 NODE  network=aegis-control_console-lan  profile=open (inferred)
  members: aegis-control-warden-console-bridge-1, aegis-control-signet-console-bridge-1

── DIM 1 · Egress isolation ──
  ⚠ WARN [medium] egress-capable network, profile=open — confirm this is intended (bridge / measurement / DMZ)
        · internal=false

── DIM 4 · Straddler audit (internal + open legs) ──
  ⚠ WARN [medium] justified straddler aegis-control-warden-console-bridge-1 (open leg aegis-control_console-lan) — publishes loopback only:127.0.0.1:4310 
        → expected for tcp-forward bridges; no non-loopback surface
  ⚠ WARN [medium] justified straddler aegis-control-signet-console-bridge-1 (open leg aegis-control_console-lan) — publishes loopback only:127.0.0.1:4311 
        → expected for tcp-forward bridges; no non-loopback surface

── DIM 2 · Attack surface  ·  DIM 3 · Guard / seal (active) ──
  ✓ PASS [info] control plane published loopback-only (127.0.0.1:4310)
  ✓ PASS [info] Signet published loopback-only (127.0.0.1:4311)

── DIM 5 · Registry & topic ──
  ✓ PASS [info] no gatekeeper on this node — n/a

── DIM 6 · Secrets & endpoints ──
  ✓ PASS [info] no gatekeeper/keymaster on this node — n/a

══════════════════════════════════════════════════════════════
 NODE  network=aegis-dmz_default  profile=open (inferred)
  members: aegis-dmz-redis-dmz-1, aegis-dmz-gatekeeper-dmz-1, aegis-dmz-ipfs-dmz-1

── DIM 1 · Egress isolation ──
  ⚠ WARN [medium] egress-capable network, profile=open — confirm this is intended (bridge / measurement / DMZ)
        · internal=false

── DIM 4 · Straddler audit (internal + open legs) ──
  ✓ PASS [info] no container straddles internal + open networks

── DIM 2 · Attack surface  ·  DIM 3 · Guard / seal (active) ──
  ⚠ WARN [medium] raw (unsealed) gatekeeper on loopback (127.0.0.1:4260) — admin/enumerate reachable host-locally only (resolve=200 enum=200 import=500)
        → fine if intended (e.g. the DMZ import path); seal it if it must not answer admin even on-box

── DIM 5 · Registry & topic ──
  ✓ PASS [high] registry is local-only (aegis-dmz-gatekeeper-dmz-1: 'local') — cannot gossip; topic is moot

── DIM 6 · Secrets & endpoints ──
  ⚠ WARN [high] admin API key BLANK (aegis-dmz-gatekeeper-dmz-1) — admin routes unprotected (loopback/in-network only; defense-in-depth gap)
        → set ARCHON_ADMIN_API_KEY even for internal/ephemeral nodes
  ⚠ WARN [medium] wallet passphrase not found in env here (may be set elsewhere) — confirm it's not blank

══════════════════════════════════════════════════════════════
 NODE  network=aegis-peer  profile=private (inferred)
  members: aegisb-drawbridge-b-1, aegis-hh-subject, aegis-drawbridge-1, aegis-didcomm-1, aegis-nodeb-proxy, aegisb-gatekeeper-b-1, aegis-gatekeeper-1, aegisb-didcomm-b-1

── DIM 1 · Egress isolation ──
  ✓ PASS [info] network is internal:true
  ✓ PASS [critical] no egress reached the internet (ISOLATED ENETUNREACH)

── DIM 4 · Straddler audit (internal + open legs) ──
  ✓ PASS [info] no container straddles internal + open networks

── DIM 2 · Attack surface  ·  DIM 3 · Guard / seal (active) ──
  ✓ PASS [info] no published ports on this node's containers

── DIM 5 · Registry & topic ──
  ✓ PASS [high] registry is local-only (aegisb-gatekeeper-b-1: 'local') — cannot gossip; topic is moot

── DIM 6 · Secrets & endpoints ──
  ✓ PASS [medium] admin key set (64 chars)
  ⚠ WARN [medium] wallet passphrase not found in env here (may be set elsewhere) — confirm it's not blank
  ⚠ WARN [medium] advertises a non-resolving host (https://nodeb.aegis.local) — DIDComm delivery can 502 unless HEARTHOLD_DIDCOMM_ENDPOINT overrides in-network
        · aegisb-drawbridge-b-1

══════════════════════════════════════════════════════════════
 NODE  network=aegisb_default  profile=private (inferred)
  members: aegisb-drawbridge-b-1, aegisb-keymaster-b-1, aegisb-redis-b-1, aegisb-ipfs-b-1, aegisb-cli-b-1, aegisb-gatekeeper-b-1, aegisb-didcomm-b-1

── DIM 1 · Egress isolation ──
  ✓ PASS [info] network is internal:true
  ✓ PASS [critical] no egress reached the internet (ISOLATED ENETUNREACH)

── DIM 4 · Straddler audit (internal + open legs) ──
  ✓ PASS [info] no container straddles internal + open networks

── DIM 2 · Attack surface  ·  DIM 3 · Guard / seal (active) ──
  ✓ PASS [info] no published ports on this node's containers

── DIM 5 · Registry & topic ──
  ✓ PASS [high] registry is local-only (aegisb-gatekeeper-b-1: 'local') — cannot gossip; topic is moot

── DIM 6 · Secrets & endpoints ──
  ✓ PASS [medium] admin key set (64 chars)
  ✓ PASS [medium] wallet passphrase set
  ⚠ WARN [medium] advertises a non-resolving host (https://nodeb.aegis.local) — DIDComm delivery can 502 unless HEARTHOLD_DIDCOMM_ENDPOINT overrides in-network
        · aegisb-drawbridge-b-1

══════════════════════════════════════════════════════════════
 NODE  network=archon_default  profile=private (inferred)
  members: aegis-tor-1, aegis-lnbits-1, aegis-keymaster-1, aegis-control-warden-console-bridge-1, aegis-control-warden-console-1, hearthold-verifier, aegis-lightning-mediator-1, hearthold-warden, aegis-control-signet-console-bridge-1, aegis-redis-1, hearthold-sovereign, aegis-drawbridge-1, aegis-didcomm-1, aegis-mongodb-1, aegis-cli-1, aegis-ipfs-1, aegis-drawbridge-client-1, aegis-gatekeeper-1, aegis-control-signet-console-1, aegis-ollama-1, hearthold-emissary

── DIM 1 · Egress isolation ──
  ✓ PASS [info] network is internal:true
  ✓ PASS [critical] no egress reached the internet (ISOLATED ENETUNREACH)

── DIM 4 · Straddler audit (internal + open legs) ──
  ⚠ WARN [medium] justified straddler aegis-control-warden-console-bridge-1 (open leg aegis-control_console-lan) — publishes loopback only:127.0.0.1:4310 
        → expected for tcp-forward bridges; no non-loopback surface
  ⚠ WARN [medium] justified straddler aegis-control-signet-console-bridge-1 (open leg aegis-control_console-lan) — publishes loopback only:127.0.0.1:4311 
        → expected for tcp-forward bridges; no non-loopback surface

── DIM 2 · Attack surface  ·  DIM 3 · Guard / seal (active) ──
  ✓ PASS [info] control plane published loopback-only (127.0.0.1:4310)
  ✓ PASS [info] Signet published loopback-only (127.0.0.1:4311)

── DIM 5 · Registry & topic ──
  ✓ PASS [high] registry is local-only (aegis-gatekeeper-1: 'local') — cannot gossip; topic is moot

── DIM 6 · Secrets & endpoints ──
  ✓ PASS [medium] admin key set (64 chars)
  ✓ PASS [medium] wallet passphrase set
  ⚠ WARN [medium] advertises a non-resolving host (https://sandbox.archon.local) — DIDComm delivery can 502 unless HEARTHOLD_DIDCOMM_ENDPOINT overrides in-network
        · aegis-drawbridge-1

══════════════════════════════════════════════════════════════
 NODE  network=meas1_default  profile=open (inferred)
  members: meas1-redis-1, meas1-ipfs-1, meas1-gatekeeper-1, meas1-keymaster-1

── DIM 1 · Egress isolation ──
  ⚠ WARN [medium] egress-capable network, profile=open — confirm this is intended (bridge / measurement / DMZ)
        · internal=false

── DIM 4 · Straddler audit (internal + open legs) ──
  ✓ PASS [info] no container straddles internal + open networks

── DIM 2 · Attack surface  ·  DIM 3 · Guard / seal (active) ──
  ✓ PASS [info] no published ports on this node's containers

── DIM 5 · Registry & topic ──
  ⚠ WARN [medium] gatekeeper exposes a gossip registry ('local,hyperswarm') — topic privacy now matters
        · meas1-gatekeeper-1
  ⚠ WARN [medium] gossip registry configured but no mediator running — gossip inactive (drift risk if one starts)

── DIM 6 · Secrets & endpoints ──
  ⚠ WARN [high] admin key is a weak/sample value ('measure-key')
        · meas1-gatekeeper-1
        → regenerate a unique key
  ⚠ WARN [medium] wallet passphrase is a sample value ('measure-pp')

══════════════════════════════════════════════════════════════
 NODE  network=meas2_default  profile=open (inferred)
  members: meas2-ipfs-1, meas2-redis-1, meas2-keymaster-1, meas2-gatekeeper-1

── DIM 1 · Egress isolation ──
  ⚠ WARN [medium] egress-capable network, profile=open — confirm this is intended (bridge / measurement / DMZ)
        · internal=false

── DIM 4 · Straddler audit (internal + open legs) ──
  ✓ PASS [info] no container straddles internal + open networks

── DIM 2 · Attack surface  ·  DIM 3 · Guard / seal (active) ──
  ✓ PASS [info] no published ports on this node's containers

── DIM 5 · Registry & topic ──
  ⚠ WARN [medium] gatekeeper exposes a gossip registry ('local,hyperswarm') — topic privacy now matters
        · meas2-gatekeeper-1
  ⚠ WARN [medium] gossip registry configured but no mediator running — gossip inactive (drift risk if one starts)

── DIM 6 · Secrets & endpoints ──
  ⚠ WARN [high] admin key is a weak/sample value ('measure-key')
        · meas2-gatekeeper-1
        → regenerate a unique key
  ⚠ WARN [medium] wallet passphrase is a sample value ('measure-pp')

══════════════════════════════════════════════════════════════
 NODE  network=sphere-mega_default  profile=sphere (inferred)
  members: sphere-mega-redis-1, sphere-mega-gatekeeper-guard-1, sphere-mega-gatekeeper-1, sphere-mega-keymaster-1, sphere-mega-hyperswarm-mediator-1, sphere-mega-ipfs-1

── DIM 1 · Egress isolation ──
  ✓ PASS [info] SPHERE node — egress is expected (hyperswarm DHT); internal=false

── DIM 4 · Straddler audit (internal + open legs) ──
  ✓ PASS [info] no container straddles internal + open networks

── DIM 2 · Attack surface  ·  DIM 3 · Guard / seal (active) ──
  ✓ PASS [high] gatekeeper 0.0.0.0:4324 SEALED (resolve=200 enumerate=403 import=403)
  ✓ PASS [high] gatekeeper :::4324 SEALED (resolve=200 enumerate=403 import=403)

── DIM 5 · Registry & topic ──
  ⚠ WARN [medium] gatekeeper exposes a gossip registry ('local,hyperswarm') — topic privacy now matters
        · sphere-mega-gatekeeper-1
  ✓ PASS [high] private topic (/aegis-sphere/7a757bc8a4c49b180757ebb83e7594337bc13ba91c2db7ccd18797d38cf13ea9, len 78)
  ⚠ WARN [medium] STOCK mediator on a private topic — exposure bounded to topic-knowers, but no peer-auth/scoping (a non-member who learns the topic can join/inject)
        · ghcr.io/archetech/hyperswarm-mediator
        → swap to aegis-secure-mediator

── DIM 6 · Secrets & endpoints ──
  ⚠ WARN [high] admin key is a weak/sample value ('measure-key')
        · sphere-mega-gatekeeper-1
        → regenerate a unique key
  ⚠ WARN [medium] wallet passphrase is a sample value ('measure-pp')

════ VERDICT ════
  35 PASS · 27 WARN · 0 FAIL   ·  score 61/100   →  POSTURE: AT RISK

── HANDOFF · what Sentinel (L6) does NOT cover ──
  A full posture = these L6 checks + Hearthold's L1–L5 review:
  · L1–L2 app/session — require-session, per-member scoping, step-up reveal, key custody (keys stay in the Signet)
  · L3 control — anti-DNS-rebinding, anti-CSRF, CORS allow-list on the control server
  · L4 read-gating — the unauth GET /did/:did residual (Archon's universal resolver, by design)
  · L5 config defaults — registry=local, control-host loopback
```

## Composition with Hearthold (L1–L5)

Sentinel covers L6 only. A full-stack posture = these rows + Hearthold's own review of:
L1–L2 app/session (require-session, per-member scoping, step-up reveal, key custody), L3 control
(anti-rebind / anti-CSRF / CORS), L4 read-gating (the unauth `GET /did/:did` residual — Archon's universal
resolver, by design), L5 config defaults (registry=local, control-host loopback). The L6 secure-by-default
rows are in `AEGIS-L6-AUDIT-ROWS.md`.
