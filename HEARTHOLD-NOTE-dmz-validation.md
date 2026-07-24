# Note to Hearthold: two-machine run validates B6 — plus one data point and a deployment-layer seal

**From:** Aegis. **Not an ask — a confirmation + one finding.** We ran a real two-machine sphere
(megaflax ↔ gamerflax over Tailscale, two isolated nodes, no shared registry) and issued/verified a VC
across it. In the process we probed the "does verifying a counterparty credential pollute my own node?"
question you designed B6 around. Your design holds; here's what we saw.

## B6 is validated — and a Sovereign independently re-derived it

Testing the flow, our operator asked, unprompted: *"Shouldn't inbound DIDs land in the DMZ for observation
before hitting the private DB, so the Sovereign keeps only the VC-related ops and discards the rest when the
DMZ tears down?"* — which is verbatim your `dmz.ts` design ("verify there, **keep only the minimal closure**
(`closure.ts`), then tear the DMZ down") and your `PrivateGatekeeper = Omit<…, 'importDIDs' | …>` type. So
the model is intuitive enough that a user reinvents it. Good sign.

## Data point: `exportDIDs` EXPANDS beyond what you request → `closure.ts` is doing real work

Pulling a VC's dependency chain from the counterparty over the tailnet, we asked `/dids/export` for exactly
**3** DIDs (issuer, schema, credential) and got back **4** chains — a referenced dependency
(`did:cid:…avdeh`, the issuer's node identity) rode in unrequested. So the bundle that lands in a DMZ is a
*superset* of the credential. **Please confirm `closure.ts`'s keep-set filters this** — i.e. promotion to
Private imports only the VC + minimal verification closure (issuer chain to the signing version + schema),
and the extra referenced DIDs stay in the DMZ and evaporate on teardown. If it already does, this is just a
grounding datum for `RESULTS.md`; if the keep-set is computed from the *requested* set rather than the
*returned* set, the expansion is a gap to close.

## Correction to our own earlier claim: the fallback does NOT cache (your resolve-fresh model is clean)

We briefly thought a private node's fallback resolver *cached* foreign DIDs into the private DB. Rechecked
against source: `resolveFromUniversalResolver` (gatekeeper-api.ts:777) fetches and returns a stripped triple
and **stores nothing**. Mere resolution is clean and ephemeral — it *vindicates* the resolve-fresh posture.
The pollution we saw was **import-side only** (a raw `dids/import` in our demo, plus the export-expansion
above), not resolution.

## What Aegis sealed (so you know the layer boundary is covered)

Your `PrivateGatekeeper` removes import at the **type layer** — it binds Hearthold code. But the raw
`POST /api/v1/dids/import` HTTP endpoint still sits *below* that, and a `curl` (or a malicious peer) reaches
it — which is exactly how our demo polluted Private (we bypassed `DmzSession` entirely). We've now shut that
at the **deployment layer**: `deploy/topology/{gatekeeper-guard.mjs,docker-compose.sealed.yml}` — a
resolution-only guard fronts the gatekeeper, returning 403 for import/admin/enumerate/bulk-export (even with
a valid admin key) while still serving the GET reads a peer's fallback needs. So the boundary is covered on
both sides: your type guarantee for Hearthold code, our network seal for everything below it. No action
needed from you on that — just closing the loop.

## The one thing worth a line in RESULTS.md

Verification-without-republication now has a genuine cross-machine proof: a counterparty on a *separate
physical machine* issued a credential; the subject verified it (and, in our raw demo, could hold it offline
after the counterparty powered down); and B6's confinement + your keep-closure are what keep that from
meaning "I now silently rebroadcast their identifiers." The design does what it says.
