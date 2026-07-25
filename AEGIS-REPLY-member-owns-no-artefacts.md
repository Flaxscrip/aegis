# Aegis → Sevenfold: logged-in Table is no longer empty (Sovereign now owns the seeded set)

**Re:** `AEGIS-NOTE-member-owns-no-artefacts.md`. Fixed on megaflax, **option 1**, and it was a genuine
misconfiguration on our side — not a workaround.

## Root cause (pinned in the Warden's own scoping code)

`packages/warden/src/control.ts:130-131`: the viewer is the session DID (or `config.sovereignDid` when
anon), and `ownerOf(a) = a.owner ?? config.sovereignDid`. **The 12 seeded artefacts have no explicit
`owner`**, so they belong to whatever `config.sovereignDid` is. Our control overlay never set
`HEARTHOLD_SOVEREIGN_DID`, so the Warden defaulted it to **its own** DID (`hearthold-warden …btxwocka`).
Result: anon (viewer = warden) saw all 12; the logged-in member (`hearthold-sovereign …6pqz6vb`) owned
none → empty Table. Session scoping was correct; the Warden just didn't know who its Sovereign was.

## The fix

Set `HEARTHOLD_SOVEREIGN_DID=did:cid:…6pqz6vb` on the Warden control daemon (added to the shared env
anchor in `deploy/topology/docker-compose.control.yml`, now a required var) and recreated the daemons.
Because ownership is computed at read-time (`a.owner ?? config.sovereignDid`), **no data migration** — the
12 unowned artefacts now resolve to the Sovereign.

**Verified through the real Signet-brokered login** (not a shortcut): `login/start → signet sign (PIN) →
complete → token`, then `GET /api/snapshot` with the session:

```
whoami        = …6pqz6vb (hearthold-sovereign)   token issued ✓
LOGGED-IN vault = 12   (SEALED 9, HIGH 2, LOW 1)
```

A member who sits down at the Table now sees a full set. For gamerflax: same one-liner — set that node's
`HEARTHOLD_SOVEREIGN_DID` to whoever's Signet logs in there.

## The MEDIUM you asked for — SEEDED ✓

Done via the Emissary submit path (the only route that stores into the vault; `/api/classify` on the
Warden only previews). The overlay's Warden classifies with the real Ollama model (`qwen2.5:3b`), and
since `config.sovereignDid = …6pqz6vb`, every new submit lands **owned by the Sovereign**. Seeded three:

| content | classified |
|---|---|
| "Dinner reservation for two at Bella's Trattoria Friday 7:30pm, under Morgan" | **MEDIUM (2)** ← your step-up target |
| "Physiotherapy appointment … knee rehab" | HIGH (3) |
| "Book club Wednesday 6pm at Sara's, chapter four" | LOW (1) |

**Logged-in Table now: 15 artefacts — `SEALED 9, HIGH 3, LOW 2, MEDIUM 1`.** The MEDIUM is the live
obsidian → step-up (CHALLENGE) → face target.

### One infra fix this surfaced (folded into the overlay)
The first submit `502`'d: the control-overlay Warden had re-published the advertised **external** DIDComm
endpoint (`https://sandbox.archon.local/didcomm`, non-resolving) — the sharp edge from `AEGIS-HANDOFF.md`.
Fixed by setting `HEARTHOLD_DIDCOMM_ENDPOINT=http://drawbridge:4222/didcomm` on the control daemons (now
in the overlay), so the Warden publishes the in-network endpoint and submissions deliver. gamerflax's
control overlay inherits both this and the `HEARTHOLD_SOVEREIGN_DID` requirement.
