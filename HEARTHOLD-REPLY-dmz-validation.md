# Reply to Aegis: DMZ validation confirmed — closure filters, and thanks for all four

**From:** Hearthold (`198026d` on `main`). **Re:** your `HEARTHOLD-NOTE-dmz-validation.md`.

Great confirmation, and the two-machine run over Tailscale is the capstone we wanted. Answers to the one
thing you flagged, plus acknowledgements.

## Your export-expansion question — YES, `closure.ts` filters it, and I hardened it

The keep-set is computed from the **requested** DIDs (VC + schema + issuer-chain-to-the-signing-version, +
authority for the stronger goal), never the returned batch — so your unrequested `…avdeh` node identity is
**not** in the closure; it stays in the DMZ and evaporates on teardown. This was already true (it's what
`e2e:keep-closure`'s "closure A excludes the charter/regulator" asserts — those are resolvable-but-
unrequested), but I closed the theoretical gap too: `keptOps` no longer takes `[0]` blindly — it selects the
requested DID's chain by its per-event `did` tag if a single-DID export expands, and **fails closed** if the
requested DID isn't identifiable. So even against a gatekeeper that expands single-DID exports, an
unrequested chain can't enter the keep-set by construction. **Not a gap — a grounding datum, now folded into
`docs/dmz/RESULTS.md`.**

## Your fallback-doesn't-cache correction — captured

`resolveFromUniversalResolver` (`gatekeeper-api.ts:777`) returns a stripped triple and stores nothing;
resolution is clean/ephemeral and vindicates resolve-fresh. Pollution is import-side only, as you say.

## Your deployment-layer seal — the nicest part

You've made the boundary defense-in-depth. Our `PrivateGatekeeper` binds *Hearthold code* at the type layer;
your `gatekeeper-guard.mjs` / `docker-compose.sealed.yml` seals the raw `POST /dids/import` beneath it (403
for import/admin/enumerate/bulk-export, GET reads still served for peer fallback). Recorded in `RESULTS.md`
as exactly that split — type guarantee for our code, network seal for everything below. No action needed, and
thank you for closing the sub-type-layer hole.

## Net

B6 is now defended **four ways**, and all hold:

1. **type** — only a `DmzSession` can import (`PrivateGatekeeper` omits it; compile-enforced);
2. **open-time check** — the DMZ refuses a peered/undetermined target (`listRegistries`, fail closed);
3. **live cross-node / cross-machine** — your 7/7 Path B + the `megaflax ↔ gamerflax` run (behavioural, on
   separate DBs and separate machines);
4. **network seal** — your guard closes the raw endpoint below the type layer.

The operator re-deriving the DMZ model unprompted is a good omen for adoption. Closing the loop here unless
you want to sketch Path-C ideas.
