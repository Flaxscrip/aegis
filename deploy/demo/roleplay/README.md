# Role-play toolkit — drive the agents by hand

Thin wrappers that inject commands into the right isolated container, so a
person can *operate* each Hearthold agent during a live demo without the verbose
`docker compose exec` incantation. They live in the **Aegis** repo (they access
the isolated sandbox containers) and touch only Hearthold's public agent CLIs +
the Sovereign control API — Hearthold's repo is not modified.

All commands run in the shared `/data/roleplay` data root (passphrase `roleplay`;
both overridable via `ROLEPLAY_ROOT` / `ROLEPLAY_PASS`, and `HEARTHOLD_DIR` for
the compose file location).

## The cast

| Script | Who | Container / identity |
|--------|-----|----------------------|
| `sovereign` | **You** — the principal, holding the Signet | `sovereign`, `/data/roleplay/sovereign` |
| `signet` | **Your** second-factor approval gate (Signet) | `sovereign` control daemon, `127.0.0.1:4311` |
| `warden` | **Your** home custodian | `warden`, `/data/roleplay/warden` |
| `bank` | Meridian Capital **Bank** — the issuer (demo runner) | `sovereign` binary, `/data/roleplay/bank` (distinct identity) |
| `fund` | Meridian Growth **Fund** — the verifier (demo runner) | `verifier`, `/data/roleplay/verifier` |

## Quick start

```bash
cd deploy/demo/roleplay
./setup                     # provision Sovereign + Bank + Fund (idempotent; --fresh to reset)
```

Then the accredited-investor scenario:

```bash
# 1. the bank issues you a credential (its signature is what the fund will trust)
./bank issue <sovereignDid> AccreditedInvestor authority='Meridian Capital' tier=accredited

# 2. you accept it into your wallet
./sovereign accept <credDid>
./sovereign issued                       # confirm it's in your vault

# 3. you arm your Signet so disclosures gate through your PIN
./signet arm 1379

# 4. the fund asks you to prove accreditation (routes to your Signet)
./fund verify <sovereignDid> <schemaDid> <bankDid> tier=accredited

# 5. you decide — see the request, then approve (or deny) with your PIN
./signet pending
./signet approve 1379                     # or: ./signet deny

# 6. the fund reads back ✓ VERIFIED (tier=accredited) — trusting the BANK, never seeing your data
```

`setup` prints all the DIDs; `./sovereign status`, `./bank status`, `./fund
status` show them too.

## Notes

- **`signet`** drives the Sovereign control daemon's localhost API
  (`arm` / `pending` / `approve` / `deny`) so approvals work non-interactively —
  ideal for a scripted or chat-driven walkthrough. `./signet tui` launches the
  interactive Ink approver instead, for a live terminal.
- Everything is on the air-gapped node: no command here reaches the internet.
- These are demo drivers, not production tooling — the passphrase and PIN are
  fixed demo values.
