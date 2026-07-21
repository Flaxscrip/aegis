# Aegis — Archon, air-gapped

**Aegis is a fork of [Archon](https://github.com/archetech/archon) carrying a
fully self-contained, egress-isolated sandbox profile.** It proves that a
complete `did:cid` self-sovereign-identity stack — identity, verifiable
credentials, encrypted messaging, vaults, Lightning payments, DIDComm
messaging, and an on-device AI classifier — can run with **zero internet
access at runtime**, the way an air-gapped hackathon or high-assurance
deployment demands.

The upstream Archon README follows below; everything Aegis-specific is the
overlay described here. The name refers to the shield: Aegis is the thing
guarding the isolation boundary.

## What the overlay adds

Everything is layered *on top of* an unmodified Archon node — the base
services are configured, not patched, so this stays close to a reference
deployment. The full, reproducible writeup with every command, failure
diagnosed, and acceptance transcript is in **[SANDBOX-PROFILE.md](SANDBOX-PROFILE.md)**.

| Piece | What it is |
|-------|-----------|
| `docker-compose.override.yml` | The core of the profile: one `internal: true` network that cuts every container off from the internet, plus the DIDComm relay's in-network delivery opt-in. |
| `docker-compose.lightning-regtest.yml` | A local regtest Bitcoin + two-node LND network — one Lightning invoice paid between nodes, fully offline. |
| `docker-compose.lightning-zap.yml` | Archon's *own* Lightning subsystem (CLN + LNbits + Drawbridge + lightning-mediator) — a DID-to-DID zap, offline, driven through Keymaster. |
| `docker-compose.ollama.yml` | A containerized Ollama on the isolated network, serving the host's already-pulled models via a read-only mount — on-device classification with no egress. |
| `scripts/sandbox/cln-lightningd-wrapper.sh` | Fix for a vendor CLN image that generates config for plugins it doesn't ship. |
| `packages/clients/src/keymaster-{client,types}.ts` | A genuine client/server parity fix (`verifyProof` was server-only) — a candidate to upstream to Archon, not sandbox-specific. |

The registry is `local` — Archon's built-in DB-only registry that never
queues a DID operation to any mediator — so identity create/update/resolve,
credentials, messaging, and vaults all work with no gossip, no chain, no
network of any kind.

## Runtime isolation, in one line

The whole profile rests on one property, proven repeatedly in
SANDBOX-PROFILE.md: every container is on a Docker network created
`internal: true`, so a dial to any public IP hard-fails `ENETUNREACH` and
DNS fails `EAI_AGAIN` — while in-network service-to-service traffic (and
host-published API ports) keep working. Images are *built* with internet
(npm, base images, model weights); nothing needs it once *running*.

## What runs on top

[Hearthold](https://github.com/flaxscrip/hearthold) — a home-custodian /
world-companion agent app — runs entirely inside this isolated network as a
downstream consumer, exercising DIDComm messaging, verifiable-credential
evidence graphs, and the on-device classifier. It lives in its own repo; the
node-side settings it needs are documented in SANDBOX-PROFILE.md §11.

## Quick start

```bash
cp sample.env .env          # then edit per SANDBOX-PROFILE.md §2
docker compose --env-file .env up -d   # override.yml auto-loads; node comes up isolated
```

See **[SANDBOX-PROFILE.md](SANDBOX-PROFILE.md)** for the isolation proof, the
acceptance suite, both Lightning stretch goals, and the DIDComm + Ollama
add-ons.

---
