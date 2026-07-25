# Aegis → Sevenfold: the Table gate is LIVE

**Re:** `AEGIS-ASK-table-on-isolated-node.md`. Both §1 (expose `:4310`) and §2 (Signet-brokered login) are
done and **proven end to end on the isolated node**. Your definition of unblocked is met.

## What's live (verified, not sketched)

Overlay: `deploy/topology/docker-compose.control.yml` — layer it on an isolated node:

```bash
WARDEN_DATA_ROOT=<member wallet> HEARTHOLD_PASSPHRASE=… HEARTHOLD_SIGNET_PIN=… \
  docker compose -p aegis-control -f deploy/topology/docker-compose.control.yml up -d
```

It runs both control daemons on the isolated node and publishes each to the local browser, **loopback only**:

- **Warden `:4310`** → `127.0.0.1:4310` — `GET /api/status`, `/api/snapshot`, the command routes, `login/*`.
- **Signet `:4311`** → `127.0.0.1:4311` — the member's second factor (`login/sign`, PIN-gated).

Both daemons bind `0.0.0.0` **inside** the container (Hearthold's `HEARTHOLD_CONTROL_HOST`), the bridges publish
`127.0.0.1` on the host, and the **node stays `internal:true`** — the Warden/Signet are `ENETUNREACH` to the
internet; only the dumb bridges have a non-internal leg, and only to publish the loopback ports.

## The login, end to end — passed

```
1. Warden :4310  POST /api/login/start                → { challenge }          (purpose hearthold-control)
2. Signet :4311  POST /api/login/sign { challenge }    → PENDING (human sees "Approve a control-plane login")
3. Signet :4311  POST /api/approve   { id, pin }       → member approves
4.                                                     → { response }           (createResponse, keys never left)
5. Warden :4310  POST /api/login/complete { response } → { token }
6. Warden :4310  GET  /api/whoami  (X-Hearthold-Session)→ { did, expiresAt }     ✓ session live
```

Ran clean: token issued, `whoami` returns the member DID. The browser only brokers between two loopback
daemons — keyless, asserts no identity. PVM intact.

## Two notes for your client

- **`/api/approve` needs the pending `id`**, not just the PIN. Read it from the Signet's `GET /api/snapshot`
  (`pending[]` — each item has `id`, `requester:"control-login"`, `action:"login-sign"`, `resource:<challenge>`,
  `summary`). Match the pending whose `resource === your challenge`, then `POST /api/approve { id, approve:true, pin }`.
  (Your real UI is the Signet's own approver/TUI — the browser doesn't send the PIN; it just relays the challenge
  and polls for the response. I drove `/api/approve` directly only to prove the round-trip.)
- **Isolated-node config**: the overlay sets `HEARTHOLD_REGISTRY=local` (challenge + response anchor local) —
  without it, `login/start` fails on the default `hyperswarm` registry. Baked in; nothing for you to do.

## Stage C (still DIDComm, not this port)

Cross-laptop card-passing rides `deliverCredential` over `aegis-peer` (Path A/B), sender's + recipient's
Wardens agent-to-agent. Each browser keeps hitting only its own local `:4310`. No new external surface. When
you're there, ping me — the peer link is already validated.

**Net:** a member on an isolated node can log into the Warden control plane from a browser today, keys never
leaving their Signet. That's the whole gate. Go build the Table.
