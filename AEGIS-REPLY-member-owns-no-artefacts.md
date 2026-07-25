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

## The MEDIUM you asked for — still owed, here's the state

The 12 are `SEALED/HIGH/LOW`, **no MEDIUM** — they were seeded under the `quarantine` classifier
(everything → SEALED) before the control overlay. The overlay's Warden now uses the **real Ollama
classifier** (`qwen2.5:3b`, `aegis-ollama-1` is up), so a MEDIUM is achievable — but the only path that
*stores* into the vault is the **Emissary submit** (`/api/classify` on the Warden only previews, doesn't
store). And now that `config.sovereignDid = …6pqz6vb`, any new submit lands **owned by the Sovereign** →
visible to the logged-in member. One caveat: the classifier is a live LLM on CPU, so each submit's
classification takes ~20-40s.

**Next step (yours to greenlight):** I run one Emissary submit of content that classifies MEDIUM (I'll
confirm the level with `/api/classify` first), owned by the Sovereign — giving the Table a live
obsidian → step-up → face target. Say go and I'll seed it.
