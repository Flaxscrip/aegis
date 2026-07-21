# Aegis — C:\DIR demo script

**Thesis: privacy and auditability are not opposites.** With issuer-attested,
selectively-disclosed evidence, an auditor gets cryptographic proof of exactly
the fact they need — and provably nothing more — while the sensitive data never
leaves an air-gapped boundary. This demo shows a full self-sovereign-identity
*and payments* stack doing that with the network cord cut.

Two acts, building on each other:

1. **Privacy-forward** — prove a compliance fact without disclosing the data behind it.
2. **Privacy-forward payment** — a private payment an auditor can still verify was authorized.

Audience framing (C:\DIR): every beat should answer the auditor/regulator's real
question — *"how do I get assurance without a surveillance ledger?"* — not just
show a crypto trick.

---

## Why this matters to an auditor (the one-slide version)

Regulators fear that privacy means opacity: if the customer's data is hidden,
how does anyone verify compliance? Aegis answers structurally:

- **Issuer-attested.** A fact is trusted because the *issuer* signed it (a bank,
  a KYC provider, a regulator), never because a custodian vouches for it.
- **Selective disclosure.** A Merkle-rooted evidence graph lets the holder reveal
  *one* leaf — "income > threshold", "KYC passed", "authorized to spend" — and
  prove the rest exists without showing it.
- **Human-in-the-loop.** Sensitive disclosures require a second-factor co-sign
  (the Signet), so an AI agent can never silently exfiltrate on the user's behalf.
- **Air-gapped.** All of it runs on a node with zero internet egress, so the raw
  identity documents never cross the institution's boundary.

The result an auditor actually wants: *cryptographic certainty about the specific
facts under audit, with a verifiable human-approval trail, and no bulk data
exposure.*

---

## Pre-flight (before the room is watching)

Run once, confirm green, leave it up. Full bring-up is in `SANDBOX-PROFILE.md`;
for a truly air-gapped venue, deploy from the offline bundle first
(`deploy/offline/README.md`).

```bash
# 1. Stack healthy + all capabilities on
docker exec archon-cli-1 node -e \
  "require('http').get('http://drawbridge:4222/api/v1/capabilities',r=>{let b='';r.on('data',c=>b+=c);r.on('end',()=>console.log(b))})"
# want: {"didcomm":true,"lightning":true,"names":true}

# 2. Warden's mailbox poller is running (Hearthold flows hang without it)
docker exec hearthold-warden sh -c 'ps aux | grep -q "[s]erve" || echo "START serve first"'

# 3. Classifier is warm (first inference cold-loads ~10s; pre-warm so the demo pops)
docker compose -f ~/hearthold/docker-compose.hearthold.yml exec -T warden \
  node packages/warden/dist/index.js classify location "pre-warm" >/dev/null

# 4. Payer wallet is funded (Act 2)
#    warden-test should show a positive LN balance (~75000 sats from setup)
```

**Terminal layout for the live run:** three panes —
`ISOLATION` (proofs), `AGENT` (Warden/Emissary/Signet TUIs), `AUDITOR` (verifier).
The split makes the trust boundary visible: the auditor pane never runs a command
that could see raw data.

Timing: Act 0 ~2 min, Act 1 ~6 min, Act 2 ~6 min. ~15 min + questions.

---

## ACT 0 — "The cord is cut" (~2 min, the hook)

**Say:** "Everything you're about to see — identities, credentials, a payment —
runs on this one box, with no internet. Not 'we don't call out much.' *Cannot.*"

**Show:**
```bash
# The whole stack is on a Docker network created internal:true — no route out.
docker exec archon-gatekeeper-1 node -e \
  'require("http").get({host:"1.1.1.1",port:80,timeout:5000},()=>{}).on("error",e=>console.log("egress →",e.code))'
# → egress → ENETUNREACH

docker exec hearthold-warden node -e \
  'require("dns").lookup("google.com",(e)=>console.log("dns →", e ? e.code : "RESOLVED"))'
# → dns → EAI_AGAIN
```
For maximum theatre at an air-gapped venue: physically unplug first, *then* run the demo.

**Why (auditor):** "For a regulated institution this is the difference between a
policy promise and a physical guarantee. Your customers' identity data never
leaves a boundary you can point at."

**Aha:** A complete SSI + payments stack that keeps running with the network gone.

---

## ACT 1 — Prove a fact without spilling the data (~6 min, the privacy core)

**Scenario:** A customer must prove a compliance-relevant fact — say *"my income
exceeds the accredited-investor threshold"* — to a relying party (a fund, an
onboarding desk). Today that means emailing bank statements. Here, they prove the
*fact* and disclose *nothing else*.

The Warden (home custodian) holds the private history; the Emissary (world-facing
companion) carries only a revocable delegation; the Sovereign (Signet, 2nd device)
authorizes sensitive releases. This mirrors control-plane / data-plane separation —
no single agent can reconstruct the whole.

### Beat 1 — the private artefact never leaves, and the AI that reads it can't phone home
**Say:** "The customer's Emissary observes a private financial document. An
on-device model classifies its sensitivity — and that model has no internet
either."

**Show** (Emissary TUI, or CLI):
```bash
~/hearthold/deploy/sandbox/run-emissary-tui.sh          # interactive
# submit → "2024 brokerage statement, acct ****8891, YTD income $214,500"
# → classified sensitivity 3 (HIGH) → sealed at rest (ciphertext in the vault)
```
**Why:** "The document is sealed. Even the custodian stores only ciphertext. And
the classification decision was made locally — nothing about this document was
sent to a cloud AI."

### Beat 2 — mint an issuer-attested, Merkle-rooted evidence graph
**Say:** "When a relying party asks for proof, the Warden assembles supporting
observations into a signed evidence graph — Merkle-rooted, so each fact is a leaf
under one root."

**Show** (the verified flow — evidence graph + selective disclosure + Signet co-sign):
```bash
~/hearthold/deploy/sandbox/run-evidence.sh
```
This runs three things end-to-end (all green in-container):
- `evidence` — assemble → mint a **signed** graph → verify (trust class: *witnessed*)
- `evidence-selective` — **reveal one leaf against the root, hide the rest**
- `evidence-stepup` — the Sovereign's Signet co-sign, embedded and independently verifiable

### Beat 3 — the money shot: selective disclosure
**Say:** "Here's the whole point. The auditor asked one question. They get one
answer — *income exceeds the threshold* — proven against the Merkle root. Every
other fact in that graph stays sealed, and they can see it's sealed, not absent."

**Show:** the `evidence-selective` output — one revealed leaf, the siblings shown
as hashes only, verification passing against the root.

**Why (auditor):** "This is what a privacy-preserving audit looks like: certainty
about the fact in scope, cryptographic proof that the holder isn't hiding a
*different* answer, and zero bulk disclosure."

### Beat 4 — human-in-the-loop step-up (proof-of-human)
**Say:** "The document was HIGH sensitivity, so releasing anything derived from it
required a second factor. The Sovereign — a separate device, the Signet — had to
co-sign with a PIN."

**Show** (Signet TUI, the co-sign prompt from Beat 2's step-up):
```bash
~/hearthold/deploy/sandbox/run-signet-tui.sh <PIN>
```
**Why:** "For an institution deploying AI agents, this is the guardrail regulators
will ask for first: an autonomous agent *cannot* disclose sensitive data without a
provable human approval. The approval is embedded in the evidence a third party
verifies — not a log we ask them to trust."

**Act 1 close:** "The relying party verified the *issuer's* signature. They never
saw the statement. They never saw our node. And a human provably approved the
release."

---

## ACT 2 — A private payment an auditor can still verify (~6 min, the financial core)

**Scenario:** A payment must be private — counterparties and amount are nobody
else's business — yet an auditor must be able to confirm *"the payer was an
authorized/KYC'd party"* after the fact, without seeing who paid whom or how much.

This is the pattern that makes regulators nervous about both extremes: a fully
public ledger is a surveillance engine; a fully opaque one is unauditable. Aegis
gives the third option.

### Beat 1 — the payer holds an issuer-signed authorization credential
**Say:** "First, a regulator or membership authority issues the payer a credential
— think 'KYC-verified' or 'authorized to transact'. Issued and verified entirely
offline."

**Show** (the prove flow — an issuer issues a membership credential, a verifier
challenges the holder to prove it, gated by the Signet PIN):
```bash
~/hearthold/deploy/sandbox/run-prove.sh setup     # issuer issues the credential
~/hearthold/deploy/sandbox/run-prove.sh verify    # verifier challenges → Signet PIN → proven
```
**Why:** "Trust rests on the *issuer's* signature. The verifier confirms the payer
is authorized without the payer handing over any identity documents — same
selective-disclosure principle as Act 1."

### Beat 2 — the private, DID-to-DID payment
**Say:** "Now the payment itself — addressed by decentralized identifier, settled
over Lightning, on our air-gapped node."

**Show** (real DID-to-DID zap through Keymaster; balances move; fully offline —
verified in SANDBOX-PROFILE.md §9):
```bash
# payer (warden-test) balance before
ADMIN_KEY=$(grep ^ARCHON_ADMIN_API_KEY= ~/isolation/archon/.env | cut -d= -f2)
lnbal() { docker exec archon-cli-1 node -e "const h=require('http');const r=h.request({hostname:'keymaster',port:4226,path:'/api/v1/lightning/balance',method:'POST',headers:{'Content-Type':'application/json','Content-Length':2,'X-Archon-Admin-Key':'$ADMIN_KEY'}},x=>{let b='';x.on('data',c=>b+=c);x.on('end',()=>console.log(b))});r.end('{}')"; }

# the zap: payer → payee by DID, amount + memo (see §9 for the full call)
#   POST /api/v1/lightning/zap {did:<payee DID>, amount:10000, memo:"invoice 7781"}
# → {"paymentHash":"..."}   balances shift by exactly the amount
```
**Why:** "The payee is addressed by DID — and Hearthold issues a *fresh pairwise
DID per counterparty*, so there's no stable public identifier tying transactions
together. No bank-style ledger exposing the customer's entire payment graph."

### Beat 3 — the auditor's view: authorized, without the details
**Say:** "Here's the compliance question an auditor actually has: *was this payment
made by an authorized party?* Not *who, how much, to whom.* We answer exactly that."

**The composition (be explicit — this is two verifiable halves, honestly joined):**
- The payment carries **no identity** — just a paymentHash and a pairwise DID.
- The authorization credential carries **no payment detail** — just "this party is
  authorized," issuer-signed.
- The payer's Emissary records the payment as an **observation** ("settled invoice
  7781 under authorization <cred>"), which the Warden can fold into an evidence
  graph and **selectively disclose** to the auditor: *"an authorized party settled
  a compliant payment"* — revealing the compliance leaf, hiding counterparty and
  amount.

**Show:** re-run the Act 1 evidence/selective-disclosure flow over the
payment-observation, revealing only the compliance leaf; the auditor verifies the
issuer's credential signature and the Warden's graph signature.

**Why (auditor):** "The auditor gets provable authorization and a verifiable
human-approval trail. They do *not* get a surveillance feed of the customer's
finances. That's privacy-preserving compliance — and every signature checks out
with the network unplugged."

**Act 2 close:** "Same primitive, two domains: prove the fact under audit, disclose
nothing else. In Act 1 it was income. Here it's payment authorization."

---

## Closing (~1 min)

**Say:** "You don't have to choose between customer privacy and auditability.
Issuer-attested, selectively-disclosed evidence gives auditors cryptographic proof
of exactly the facts they need, with a human-approval trail they can verify
themselves — and the whole stack runs air-gapped, so the sensitive data never
leaves your walls. Identity, credentials, and payments, with the cord cut."

**Leave-behind:** `https://github.com/flaxscrip/aegis` — the reproducible profile,
the isolation proofs, and this script. The offline bundle boots it on a
disconnected box.

---

## Honesty notes (for us, not the room)

- **Act 1** is one verified, self-contained flow (`run-evidence.sh`): evidence
  graph, selective disclosure, and Signet co-sign are built and green in-container.
- **Act 2** *composes* real primitives: issuer-signed credential proof
  (`run-prove.sh`, real), a real DID-to-DID zap (§9, real), and the evidence/
  selective-disclosure machinery from Act 1 applied to a payment-observation. The
  paymentHash and the credential are joined **at the evidence-graph layer**, not by
  a single built-in "gated payment" primitive — say "composed from these parts,"
  don't imply a cryptographic payment-credential binding that doesn't exist yet.
  (A native gate — refuse the zap unless the payer proves the credential — is a
  clean roadmap item; note it if asked, don't demo it as built.)
- **Fallbacks:** if the Emissary submit→serve path is flaky on the day, Act 2 Beat 3
  still stands on its two halves shown independently (credential proof + zap); skip
  the payment-observation graph rather than fight it live. Always confirm
  `warden serve` is running in pre-flight — a hung submit is almost always that.
- Keep the classifier pre-warmed (pre-flight step 3); a cold first inference is
  ~10s and reads as a stall on stage.
