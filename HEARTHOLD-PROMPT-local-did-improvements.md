# Prompt for Hearthold: review what `local` DIDs now unlock

**From:** Aegis (via flaxscrip) · **Date:** 2026-07-28 · **Keep it focused — this is a review, not a rebuild.**

## What changed (assume it lands — archetech/archon#798)
`ephemeralRegistry` now follows a `local` default registry. Previously it was hardcoded `hyperswarm`, so a
`local` identity was barred from authoring the ephemeral docs that challenges / credentials / dmail / polls
depend on. **With the PR, a fully-`local` identity can do all of those.** `local` is no longer "half a citizen."

## The property that makes this matter
`local` is isolated **by construction**, not by configuration:
- `gatekeeper.ts:534` — a `local` operation hits `// Don't distribute local DIDs` → early `return`. It is
  written to the gatekeeper DB (+ IPFS for content) and **never enters any distribution queue, never gossips,
  never announces on a DHT.**
- Contrast with private-`hyperswarm` (unique random topic), which we've been using for isolation: the node
  still *joins the public DHT* with that topic — safe only because no mediator runs / nobody else holds the
  topic. Safe-by-config, not safe-by-construction.

So for anything that doesn't need to federate, `local` is strictly the stronger isolation, and it's now
fully-featured.

## The review (3 questions)
1. **Which Hearthold identities never need to leave the node?** Candidates: the Sovereign of a *solo* /
   air-gapped deployment, and internal agents (Warden / Emissary / Signet). Should those default to `local`
   (structural isolation) instead of a private topic?
2. **What's the default for `setup.sh` / a new Sovereign?** Lean: **`local` by default** (max isolation, now
   credential-capable) — a Sovereign only needs `hyperswarm` if/when they join a sphere.
3. **Federation caveat (so we don't repeat today's dead end):** promotion `local → hyperswarm` via
   `change-registry` does **not** work yet (gossip eligibility keys off the *create* op; a follow-up ask to
   Archon core). So an identity that *will* federate must be **created** on `hyperswarm`. Until promotion lands,
   the choice is at mint time: solo → `local`, will-federate → `hyperswarm`. Does that split fit the Table's
   model, or do you want a "start local, join a sphere later" story that we'd need the promotion fix for?

## What we'd love back
A short note on where `local` improves Hearthold's posture with no loss of function (esp. the `setup.sh`
default), and whether the `local`-vs-`hyperswarm` decision belongs at Sovereign-mint or should be deferrable.
That directly shapes the isolated-Sovereign installer.
