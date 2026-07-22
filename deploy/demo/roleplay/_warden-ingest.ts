/**
 * Role-play helper (aegis-side; injected into the hearthold-warden container by ./warden-ingest).
 * The WARDEN write-hosts a credential the Sovereign has accepted into the Sovereign's PRIVATE
 * member-key KB partition (Hearthold's VC->KB bridge) — so the custodian holds it but CANNOT read it
 * at rest. Uses the role-play identities in /data/roleplay and only public @hearthold APIs.
 *
 * Env: HEARTHOLD_CRED_DID (the accepted credential to ingest), plus the usual HEARTHOLD_* role-play vars.
 */
import {
  loadConfig,
  openKeymaster,
  ensureIdentity,
  recordIssuedCredential,
  unsealAsWarden,
  openWithKey,
  unwrapKey,
} from '@hearthold/core';
import { VaultStore } from '@hearthold/warden/store';
import { PartitionStore } from '@hearthold/warden/partition-store';
import { ingestCredentialToPartition } from '@hearthold/warden/credential-vault';

const ok = (c: unknown, m: string): void => { if (!c) throw new Error(`ASSERT: ${m}`); process.stdout.write(`  ✓ ${m}\n`); };

async function main(): Promise<void> {
  const config = loadConfig();
  const pass = process.env.HEARTHOLD_PASSPHRASE ?? 'roleplay';
  const SPACE = 'sovereign-wallet-kb';
  const credDid = process.env.HEARTHOLD_CRED_DID;
  if (!credDid) throw new Error('HEARTHOLD_CRED_DID is required');

  const sovereign = await openKeymaster('sovereign', config, pass);
  const warden = await openKeymaster('warden', config, pass);
  const sovId = await ensureIdentity(sovereign, config);
  await ensureIdentity(warden, config);

  process.stdout.write('\n▸ The Sovereign hands the accepted bank VC to the Warden\n');
  const leaf = await recordIssuedCredential(sovereign, credDid, sovereign.dataFolder);
  ok(leaf.trustClass === 'issued', `it's an \`issued\` leaf, signed by ${leaf.issuer.slice(0, 24)}…`);

  process.stdout.write("\n▸ The Warden write-hosts it into the Sovereign's PRIVATE member-key partition\n");
  const res = await ingestCredentialToPartition(warden, config, { spaceId: SPACE, ownerDid: sovId.did, leaf });
  const store = new VaultStore(warden.dataFolder);
  const art = await store.get(res.artefactId);
  ok(!!art && art.sealedTo?.partition === res.partitionId, "the VC is sealed to the Sovereign's partition");
  ok(art?.scope === 'private' && art?.owner === sovId.did, 'scoped private, owned by the Sovereign');

  process.stdout.write('\n▸ At rest, the custodian CANNOT read it (write-host / read-guest)\n');
  let wardenRead: string | null = null;
  try { wardenRead = await unsealAsWarden(warden, art!.ciphertext); } catch { wardenRead = null; }
  ok(wardenRead === null, 'unsealAsWarden FAILS — the Warden holds it but cannot read the balance at rest');

  process.stdout.write("\n▸ Only the Sovereign's key opens it (the read-guest recall path)\n");
  const partition = await new PartitionStore(warden.dataFolder).get(SPACE, sovId.did);
  const priv = await unwrapKey(sovereign, partition!.wrappedKey!);
  const text = (JSON.parse(openWithKey(warden.cipher, priv, art!.ciphertext)) as { text: string }).text;
  ok(text.length > 0, `the Sovereign recalls the fact: “${text}”`);

  process.stdout.write('\n▸ It stays linked to the bank’s signed credential — trust is the ISSUER’s\n');
  ok(art!.metadata.credentialDid === credDid && art!.metadata.trustClass === 'issued',
    'artefact links back to the signed credential (credentialDid + trustClass:issued)');

  process.stdout.write('\n✓ The bank’s balance is now private-from-the-custodian knowledge: held blind, recallable by you, still bank-provable.\n');
  process.exit(0);
}
main().catch((e: unknown) => { process.stderr.write(`warden-ingest: ${e instanceof Error ? e.message : String(e)}\n`); process.exit(1); });
