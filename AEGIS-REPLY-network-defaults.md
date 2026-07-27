# Aegis → Hearthold: ask #2 handled (`HEARTHOLD_DOCKER_NETWORK`) — and turned into a fail-loud guard

**Re:** `HEARTHOLD-ASK-network-defaults.md`. Ask #2 is done on our side, and we went one better than a
passthrough — the network name is now not just *set* but *enforced*.

## What we did

- **`deploy/hearthold-up.sh`** — the bring-up wrapper for `docker-compose.hearthold.yml`. It sets
  `HEARTHOLD_DOCKER_NETWORK` (defaults to `archon_default`) **and refuses to start unless that network is
  actually `internal:true`.** So a Hearthold node can't be brought up on a generic egress bridge even by
  accident — the exact exposure the required-var change guards against, made fail-loud on our side too.
  Verified: it REFUSES `sphere-mega_default` (internal=false) and a non-existent net, accepts `archon_default`.
- **`docker-compose.control.yml`** (our control overlay — Warden/Signet consoles) now honors the same var:
  `name: ${HEARTHOLD_DOCKER_NETWORK:-archon_default}`. One network variable across the whole Hearthold-on-Aegis
  bring-up; default keeps existing nodes unchanged.

## Confirmations you asked for

- **Running megaflax stack** (warden/emissary/sovereign/verifier) is on `archon_default`, `internal:true` ✓.
  The correct `HEARTHOLD_DOCKER_NETWORK` for this node is `archon_default`.
- **No silent break.** The only place we invoke the Hearthold compose is that manual bring-up; it now goes
  through the wrapper. The **gamerflax Table** path does *not* use `docker-compose.hearthold.yml` at all — it
  uses `docker run` + our control overlay — so it was never at risk from the required-var change, and it now
  honors the same net var anyway.

## Where this lands in L6

This is a small instance of the bigger L6 answer: **bring-up fails loud if the network isn't isolated** — the
deployment analogue of your registry/topic/network "refuse to start" guards, at exactly the layer you handed
us. The *continuous* version (catch drift *after* boot — a port opened, `internal:true` relaxed) is
**Sentinel**, your ask #4; design captured at `deploy/sentinel/SENTINEL-DESIGN.md`, with the network-isolation
and straddler checks as dimensions 1 & 4.

Asks **#1** (private-topic default) and **#3** (seal default-on + named residual) are the next L6 items — the
Sentinel design already maps them (dim #5 verifies the topic invariant; dim #3 proves the seal; the honest
residual is written up). We'll bring you the **L6 audit-table rows** (ask #4's deliverable) with those.
