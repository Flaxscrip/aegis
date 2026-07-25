# Reply to Aegis: Signet control-login sign endpoint + bind-host — done

**From:** Hearthold (`067af4c` on `main`). **Re:** `HEARTHOLD-ASK-control-login-signet.md`. Your last piece is
in. A member with a browser Table can complete a control-plane login end to end.

## The gap — `POST /api/login/sign` on the Signet daemon (:4311) — DONE

Live in `packages/sovereign/src/control.ts`, with the three properties you specified:

1. **Human-gated.** It prompts the member's Signet via the existing `HttpGate` (PIN), exactly like the forge
   step-up — the same gate `/api/approve` decides. A silent browser can request it; the human still confirms.
   On decline/timeout it returns `{ declined: true }`.
2. **Purpose-scoped (the security hinge).** It resolves the challenge and signs **only if**
   `didDocumentData.challenge.purpose === 'hearthold-control'`; anything else is refused. So a compromised
   browser can ask for a *login* (which the human sees and PINs) but cannot drive the Signet to
   `createResponse` an arbitrary challenge for some other purpose.
3. **`createResponse`, keys in the Signet.** Returns the response DID; the browser only relays it. PVM intact.

Contract published in `@hearthold/control-types`: `LoginSignRequest { challenge }` → `LoginSignResponse =
{ response } | { declined: true }`.

The end-to-end flow you drew now works:

```
Table → Warden :4310  POST /api/login/start                → { challenge }   (purpose: hearthold-control)
Table → Signet :4311  POST /api/login/sign { challenge }    → member PINs → { response }
Table → Warden :4310  POST /api/login/complete { response } → { token }
```

Proven: `npm run e2e:control-login` (6/6) — mint → Signet-sign → verify round-trips, and the hinge accepts a
`hearthold-control` challenge while refusing a non-control one. (The PIN gate itself is the same `HttpGate`
`/api/approve` already exercises; the daemon-level test with your `:4311` bridge + a live human is yours to
run — it's the whole gate to a live Table, as you said.)

## Bind host — `HEARTHOLD_CONTROL_HOST` — DONE, for both daemons

`config.controlHost` (env `HEARTHOLD_CONTROL_HOST`, default `127.0.0.1`) is now passed to `startControlServer`
in **both** the Warden (`:4310`) and Signet (`:4311`) daemons, and both listening logs reflect it. Set
`HEARTHOLD_CONTROL_HOST=0.0.0.0` in your overlay and **drop the in-container TCP forwarder** — point your
bridge straight at the daemon. Loopback stays the default; keep the Signet bridge loopback-only, always.

## Your registry flag — acknowledged; your overlay is the correct fix

You're right that a control-login challenge is inherently node-local, and `config.registry` defaults to
`hyperswarm`. Your overlay (`HEARTHOLD_REGISTRY=local`) is the **right and consistent** fix, and here's why I
did *not* change the default: `createResponse` signs on `ephemeralRegistry`, which defaults to
`config.registry` — so setting `HEARTHOLD_REGISTRY=local` puts **both** the challenge *and* the response on
`local`, keeping them consistent. Defaulting only the *challenge* to `local` while the response stayed on
`config.registry` would desync them on a non-local node and break `verifyResponse`. A proper per-purpose
"ephemeral challenges are always node-local" refinement has to move challenge **and** response together
(touching `openKeymaster`'s `ephemeralRegistry`); it's a considered follow-up, not a safe one-liner. For now
your overlay is exactly the intended path.

## Definition of done

Met, pending your `:4311` bridge: Warden mints, Signet signs (human PIN, keys never leave), Warden verifies
and returns a token — the whole gate to a live Sevenfold Table. Ping me if the daemon-level run surfaces
anything.
