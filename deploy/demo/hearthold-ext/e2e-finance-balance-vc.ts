/**
 * AEGIS demo extension (lives in the aegis repo; injected into the running Hearthold container at
 * runtime — Hearthold's repo is NOT modified). A 3rd-party BANK issues a signed Balance Statement VC
 * into the Sovereign's private KB partition.
 *
 * The bank is a genuinely distinct issuer identity (its own data root — the same "separate authority"
 * pattern run-prove uses), so no new Hearthold agent role is needed. It registers a BankBalanceStatement
 * schema with the Keymaster (a real did:cid schema asset), then issues a signed balance statement to the
 * Sovereign. The Sovereign accepts it; the Warden write-hosts it into the Sovereign's PRIVATE member-key
 * KB partition (Hearthold's VC->KB bridge) — sealed to the partition key, so the custodian holds it but
 * CANNOT read the balance at rest. Only the Sovereign's (session-rewrapped) partition key reads it back,
 * and the artefact stays linked to the bank's signed credential: trust in the figure rests on the BANK's
 * signature, never the custodian's word.
 *
 * "A bank told me my balance; my Hearthold privately knows it; my custodian can't read it; and I can
 * still prove it with the bank's own attestation."
 *
 * Uses only Hearthold's public @hearthold/core + @hearthold/warden APIs. Runs via run-balance-vc.sh,
 * which docker-cp's this file into the hearthold-warden container and runs it in a throwaway data root.
 */
import { join } from 'node:path';

import {
  loadConfig,
  openKeymaster,
  ensureIdentity,
  ensureSchema,
  issueClaim,
  acceptCredential,
  recordIssuedCredential,
  unsealAsWarden,
  openWithKey,
  unwrapKey,
} from '@hearthold/core';
import { VaultStore } from '@hearthold/warden/store';
import { PartitionStore } from '@hearthold/warden/partition-store';
import { ingestCredentialToPartition } from '@hearthold/warden/credential-vault';

const assert = (cond: unknown, msg: string): void => {
  if (!cond) throw new Error(`ASSERT: ${msg}`);
  process.stdout.write(`  ✓ ${msg}\n`);
};

/** A registered JSON schema for a bank's balance statement (becomes a real did:cid schema asset). */
const BALANCE_STATEMENT_SCHEMA = {
  $schema: 'http://json-schema.org/draft-07/schema#',
  title: 'BankBalanceStatement',
  type: 'object',
  properties: {
    type: { type: 'string', const: 'BankBalanceStatement' },
    institution: { type: 'string' },
    accountRef: { type: 'string' },
    statedBalanceUsd: { type: 'number' },
    currency: { type: 'string' },
    asOf: { type: 'string' },
  },
  required: ['type', 'institution', 'statedBalanceUsd', 'asOf'],
  additionalProperties: true,
} as const;

async function main(): Promise<void> {
  const config = loadConfig();
  const pass = 'aegis-finance-balance-vc';
  const SPACE = 'sovereign-wallet-kb';

  const warden = await openKeymaster('warden', config, pass);
  const sovereign = await openKeymaster('sovereign', config, pass);
  // The BANK: a distinct issuer identity via its OWN data root (separate wallet/seed => separate DID),
  // so it is unambiguously a third party -- no new Hearthold agent role required.
  const bankConfig = { ...config, dataRoot: join(config.dataRoot, 'meridian-bank') };
  const bank = await openKeymaster('verifier', bankConfig, pass);
  await ensureIdentity(warden, config);
  const sovId = await ensureIdentity(sovereign, config);
  const bankId = await ensureIdentity(bank, config);

  process.stdout.write('\n▸ The bank (a distinct issuer identity) registers a BankBalanceStatement schema\n');
  const schemaDid = await ensureSchema(bank, 'BankBalanceStatement', BALANCE_STATEMENT_SCHEMA);
  assert(typeof schemaDid === 'string' && schemaDid.startsWith('did:cid:'), `schema registered with the Keymaster: ${schemaDid.slice(0, 30)}…`);

  process.stdout.write('\n▸ The bank issues a signed balance statement → the Sovereign accepts it\n');
  const oneYear = new Date(Date.now() + 1000 * 60 * 60 * 24 * 365).toISOString();
  const credDid = await issueClaim(
    bank,
    sovId.did,
    schemaDid,
    {
      type: 'BankBalanceStatement',
      institution: 'Meridian Capital Bank',
      accountRef: '****8891',
      statedBalanceUsd: 4820000,
      currency: 'USD',
      asOf: '2025-12-31',
    },
    oneYear,
  );
  assert(await acceptCredential(sovereign, credDid), 'the Sovereign accepts the bank-issued balance statement');
  const leaf = await recordIssuedCredential(sovereign, credDid, sovereign.dataFolder);
  assert(leaf.trustClass === 'issued' && leaf.issuer === bankId.did, 'the accepted VC is an `issued` leaf from the bank');

  process.stdout.write("\n▸ The Warden write-hosts the balance VC into the Sovereign's private member-key partition\n");
  const res = await ingestCredentialToPartition(warden, config, { spaceId: SPACE, ownerDid: sovId.did, leaf });
  const store = new VaultStore(warden.dataFolder);
  const art = await store.get(res.artefactId);
  assert(!!art && art.sealedTo?.partition === res.partitionId, "the balance VC is sealed to the Sovereign's partition");
  assert(art?.scope === 'private' && art?.owner === sovId.did, 'it is scoped private, owned by the Sovereign');

  process.stdout.write('\n▸ At rest, the custodian CANNOT read the balance (write-host / read-guest)\n');
  let wardenRead: string | null = null;
  try {
    wardenRead = await unsealAsWarden(warden, art!.ciphertext);
  } catch {
    wardenRead = null;
  }
  assert(wardenRead === null, 'unsealAsWarden FAILS -- the Warden write-hosts but cannot read the balance at rest');

  process.stdout.write("\n▸ The Sovereign's partition key recovers the balance fact (read-guest recall)\n");
  const partition = await new PartitionStore(warden.dataFolder).get(SPACE, sovId.did);
  const priv = await unwrapKey(sovereign, partition!.wrappedKey!);
  const text = (JSON.parse(openWithKey(warden.cipher, priv, art!.ciphertext)) as { text: string }).text;
  assert(
    /Meridian Capital Bank/.test(text) && /4820000/.test(text),
    `the partition read recovers the bank's balance statement: “${text}”`,
  );

  process.stdout.write('\n▸ It stays linked to the bank’s signed credential -- trust in the figure is the ISSUER’s\n');
  assert(
    art!.metadata.credentialDid === credDid &&
      art!.metadata.issuer === bankId.did &&
      art!.metadata.trustClass === 'issued',
    'the artefact links back to the signed balance statement (credentialDid + bank issuer + trustClass:issued)',
  );

  process.stdout.write(
    '\n✓ Bank balance statement → private KB: a 3rd-party financial institution’s signed balance is\n' +
      "  private-from-the-custodian knowledge, recallable by the Sovereign, still provable via the bank.\n",
  );
  process.exit(0);
}

main().catch((err: unknown) => {
  process.stderr.write(`e2e-finance-balance-vc: ${err instanceof Error ? err.message : String(err)}\n`);
  process.exit(1);
});
