# Hearthold demo extensions (Aegis-side, runtime-injected)

Demo pieces that build on Hearthold's public APIs **without modifying the
Hearthold repo**. Each is a small TypeScript program that uses only
`@hearthold/core` + `@hearthold/warden` exports; the accompanying `run-*.sh`
`docker cp`s it into the running `hearthold-warden` container, runs it in a
throwaway data root, and removes it. Nothing is baked into the Hearthold image;
Hearthold's git tree is never touched.

This is the clean seam for Aegis-specific demo content: it lets us extend the
story (a bank issuer, a financial-institution VC, etc.) on our side, so
Hearthold stays a pristine upstream dependency we compose against.

| File | What it shows |
|------|---------------|
| `e2e-finance-balance-vc.ts` + `run-balance-vc.sh` | A 3rd-party **bank** (a distinct issuer identity, via its own data root — no new Hearthold agent role) registers a `BankBalanceStatement` schema, issues a **signed balance statement** to the Sovereign, and the Warden write-hosts it into the Sovereign's **private** member-key KB partition (Hearthold's VC→KB bridge). The custodian holds it but **cannot read the balance at rest**; the Sovereign recalls it; the artefact stays linked to the bank's signature — **trust in the figure is the issuer's, not the custodian's**. |

## Run

```bash
# with the Hearthold sandbox + Archon node up:
deploy/demo/hearthold-ext/run-balance-vc.sh
```

## Why runtime injection (not a baked image)

The Hearthold AI actively develops that repo; baking Aegis demo scripts into
`hearthold:sandbox` would entangle our commits with theirs and require rebuilds
in lockstep. Injecting at runtime keeps the boundary crisp: Hearthold ships the
capability (the VC→KB bridge, the classifier, DIDComm), Aegis composes the
demo. If a piece proves broadly useful it can be proposed upstream to Hearthold
on its own merits, rather than smuggled in via the image.
