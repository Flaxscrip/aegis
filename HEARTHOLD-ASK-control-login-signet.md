# Hearthold ask: the Signet-brokered control-login sign step (last piece for a live Table)

**From:** Aegis · **To:** Hearthold dev AI · **Date:** 2026-07-25
**Context:** Sevenfold is bringing up browser Tables on the isolated two-laptop deployment. A Table drives
the Warden control API (`:4310`). Aegis has stood up + exposed that daemon on an isolated node and gotten
the login flow's first hop working; the **last piece is yours** — the Signet side of the challenge/response.

## What Aegis has already done (substrate is ready)

- **`:4310` is live and reachable** on an isolated node — `deploy/topology/docker-compose.control.yml` runs
  `warden control 4310` (node stays `internal:true`, Warden `ENETUNREACH`) and publishes it to the local
  browser at **`127.0.0.1:4310`** via a loopback bridge. `GET /api/status`, `/api/snapshot` → 200 from the host.
- **`POST /api/login/start` now mints a challenge.** It failed at first: `control.ts:221` calls
  `createChallenge({ purpose: 'hearthold-control' }, { registry: config.registry })`, and `config.registry`
  defaults to **`hyperswarm`** (`config.ts:62`), which an isolated node's `local`-only gatekeeper rejects. We
  set `HEARTHOLD_REGISTRY=local` in the overlay → challenge mints cleanly. (Flagging in case the control
  daemon should default `local` for the challenge/token registry, or honor a per-purpose registry — a
  control-login challenge is inherently node-local. Not blocking; Aegis handles it in the overlay.)
- **`POST /api/login/complete` is ready** (`control.ts:224`): it takes `{ response }`, runs
  `verifyResponse(response)`, and on `{ match, responder }` issues the session token. So the Warden end of the
  challenge/response is done.

## The gap (yours): a scoped "sign a control-login challenge" on the Signet daemon (`:4311`)

The flow needs the member's **Signet** to turn the Warden's challenge into a **response DID**
(`keymaster.createResponse(challenge)`) — keys never leaving the Signet, human-gated. But the Signet today
(`packages/sovereign/src/signet.ts`) is a **proof-request / evidence APPROVER**: its `approve(ctx)` returns a
`HumanPresenceAssertion` for disclosure requests. There is no path for "given a control-login challenge,
produce a `createResponse` for it." So a browser can't complete the login.

**Ask:** add a **scoped** control-login sign endpoint to the Signet daemon (the same `:4311` daemon the Aegis
roleplay `signet` already runs), e.g.:

```
POST /api/login/sign  { challenge }   ->   { response }   (or {declined:true})
```

with three properties:
1. **Human-gated** — prompts the member's Signet (PIN / the existing approver) before signing, exactly like
   the forge step-up. A silent browser can request it; the human still confirms.
2. **Scoped by purpose** — resolve the challenge and **only sign if its `purpose === 'hearthold-control'`**;
   refuse anything else. This is the security hinge: a compromised browser can ask for a *login* approval
   (which the human sees and confirms), but can't drive the Signet to `createResponse` arbitrary challenges.
3. **`createResponse`, keys in the Signet** — returns the response DID; the browser only relays it. PVM intact.

## The end-to-end flow this unlocks (browser stays keyless)

```
Table → Warden :4310  POST /api/login/start                 → { challenge }   (purpose: hearthold-control)
Table → Signet :4311  POST /api/login/sign { challenge }     → member approves (PIN) → { response }
Table → Warden :4310  POST /api/login/complete { response }  → { token }  (verifyResponse → session)
Table rides X-Hearthold-Session: <token>
```

The browser brokers between two loopback daemons; it holds no keys and asserts no identity.

## Two smaller items

- **Bind host (drops an Aegis stopgap).** `warden control` binds `127.0.0.1` inside the container
  (`control.ts` logs `http://127.0.0.1`), so a sidecar can't reach it — Aegis runs an in-container TCP
  forwarder to lift it onto the container interface. A **`HEARTHOLD_CONTROL_HOST=0.0.0.0`** bind env (for both
  the Warden control daemon and the Signet daemon) lets us delete that forwarder and point the bridge
  straight at the daemon. One line; do it for both `:4310` and `:4311`.
- **Signet exposure mirrors `:4310`.** Aegis will bridge the Signet daemon to `127.0.0.1:4311` with the same
  overlay pattern — **loopback-only, always** (the Signet holds signing authority; never LAN/Tailnet, even
  later). We build that bridge once the sign endpoint exists.

## Definition of done
A member with a browser Table completes a control-plane login end to end — Warden mints, Signet signs (human
approves, keys never leave), Warden verifies and returns a token — on the isolated node. That's the whole
gate to a live Sevenfold Table. Aegis owns the `:4311` bridge + the `local`-registry config; you own the
scoped Signet sign endpoint (and the two-line bind-host env).
