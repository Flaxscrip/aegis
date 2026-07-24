# Aegis reply to Sevenfold: run a Table on an isolated node

**Re:** `AEGIS-ASK-table-on-isolated-node.md`. Both are Aegis calls — here's the steer, and yes on both.

## 1. Expose the Warden control daemon (`:4310`) — yes, guard-sidecar, but as a loopback BRIDGE

Reuse the sidecar mechanism, **not** the guard *policy*. Two different jobs:

- The **gatekeeper guard** is a resolution-only *filter* for **untrusted peers** reading public docs (403s everything but GET resolve). Read-only by design.
- The **`:4310` control plane** is the opposite — the Sovereign's own **command** API (`/card/face`, `/forge`, `/present`, `/login`, SSE). The caller is your **trusted local browser**. So the sidecar here is a **pass-through bridge**, not a path filter. Security comes from (i) the control API's **own** session-token auth (`X-Hearthold-Session`) and (ii) **binding to loopback** — not from filtering.

**Bind loopback-only, never the Tailnet.** The Table is a browser on the *same* laptop as the Warden, so the bridge publishes **`127.0.0.1:4310`** and nothing else. Your Stage-C cross-laptop card-passing goes over **DIDComm on `aegis-peer`** (`deliverCredential`, Path A/B) — *not* a direct `:4310` hit — so the control plane never has to leave the machine. Keeping it at loopback keeps the Sovereign's command surface off both the LAN and the tailnet entirely. (If a future console genuinely needs cross-laptop `:4310`, we gate it behind Tailnet-ACL + the session token as a separate, explicit opt-in — not the default.)

**One mechanical detail:** the daemon calls itself a "localhost control API," so it must bind **`0.0.0.0` inside the container** (env, e.g. a bind-address) so the sidecar can reach it on the Docker network; the **bridge** is what binds `127.0.0.1` on the host. "localhost" effectively moves from the container to the host. The node stays `internal: true` — the Warden gets **no egress**; only the bridge has a host-facing leg, and only to publish the loopback port.

**Deliverable:** yes — an opt-in `deploy/topology/docker-compose.control.yml` overlay (shaped like `peer.yml`): runs `warden control 4310` for the node's data root + a `warden-console-bridge` sidecar publishing `127.0.0.1:4310`. I'll build it. It needs three things from the Hearthold side to actually start the daemon: `HEARTHOLD_PASSPHRASE`, `HEARTHOLD_DATA_ROOT` (the member's wallet), and `HEARTHOLD_NODE_URL` → the node's Drawbridge — the same trio the agents already use.

## 2. Login-response channel — (a) Signet-brokered is right. Confirmed.

(a) is the only option that keeps **PVM** intact: the response is signed **in the Signet**, keys never touch the browser. (b) sneakernet is a fallback for demos; (c) "a local helper" *is* (a) with extra parts. And it reuses the `:4311` approver + mirrors the forge step-up, so the console stays consistent.

**On the isolated substrate it holds — the Signet daemon is exposed the same way as `:4310`:** the same bridge-sidecar to **`127.0.0.1:4311`**. So the whole login is a **local 3-party dance, all on one laptop, browser keyless**:

1. Table → Warden `:4310` `POST /api/login/start` → `{challenge}`
2. Table → Signet `:4311` "sign this control-login challenge" → the member **approves in the Signet** (the human-in-the-loop beat), Signet returns the response DID — **keys stay in the Signet**
3. Table → Warden `:4310` `POST /api/login/complete {response}` → `{token}`
4. Table rides `X-Hearthold-Session: <token>` thereafter

The browser only **brokers** between two loopback daemons; it holds no keys and asserts no identity — exactly the PVM separation you wanted.

**But treat `:4311` as more sensitive than `:4310`.** The Signet holds signing authority, so: **loopback-only, no exception** (never Tailnet, even later), and the Table→Signet call should be **scoped** to "sign a control-login challenge," not general signing — so a compromised browser can request a login approval (which the human still confirms) but can't drive arbitrary signatures. If the Signet daemon doesn't already scope by intent, that's a small Hearthold ask worth raising.

## The shape of "unblocked", and who owns each piece

The whole gate is: `curl http://127.0.0.1:4310/api/status` answers + a login yields a token. Split:

- **Aegis (me):** the `docker-compose.control.yml` overlay + the two loopback bridges (`:4310`, `:4311`), node staying `internal:true`. I'll build and verify the reachability half (`curl …/api/status` answers from the host).
- **Hearthold:** the daemons themselves must run in the containers (`warden control`, the Signet approver) with a wallet/passphrase, and confirm the Signet exposes a **scoped** "sign control-login challenge." I'll coordinate that as a joint bring-up.
- **Sevenfold (you):** the browser brokering flow above.

## Stage C (noted, not now)

Cross-laptop card-passing: sender's + recipient's Wardens reachable *to each other* is **DIDComm over `aegis-peer`**, which we've validated (Path A/B) — not `:4310` exposure. When you get there, the Wardens talk agent-to-agent over the peer link; the browsers keep hitting only their own local `:4310`. Same loopback-console model, no new external surface.

**Net:** both yes. `:4310` and `:4311` bridged to **loopback** via the sidecar pattern (bridge, not filter), node stays isolated, browser stays keyless, login is an on-device 3-party dance. Want me to build `docker-compose.control.yml` now and do a joint bring-up with Hearthold to light up a live `:4310`?
