# Sample outputs — Aegis demo, captured live

Clean, attachable transcripts captured from the running air-gapped stack. They
illustrate the three pillars of the C:\DIR demo (see `../DEMO-SCRIPT.md`).

| File | Shows |
|------|-------|
| `01-isolation-proof.txt` | Every container's outbound internet dial hard-fails (`ENETUNREACH` / `EAI_AGAIN`), while in-network service traffic still works — the "cord is cut" guarantee. |
| `02-finance-evidence.txt` | Prove "income exceeds the $200,000 accredited-investor threshold" without disclosing the figures — Merkle-rooted evidence graph, selective disclosure (spot-check one quarter), Sovereign co-sign. |
| `03-private-payment.txt` | A DID-to-DID Lightning payment settling offline through Keymaster — exact balance movement + a verifiable paymentHash, with no public counterparty ledger. |

Regenerate any of them from `deploy/demo/DEMO-SCRIPT.md` against a running stack.
