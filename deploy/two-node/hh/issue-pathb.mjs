// Counterparty issuance for Path B: warden mints a VC for a subject DID and prints all three DIDs
// (credential, schema, issuer) as JSON so the orchestrator can export each op chain. Runs in a
// hearthold container on the counterparty (node A).
import { loadConfig, openKeymaster, IDENTITY_NAME } from '@hearthold/core';

const subjectDid = process.argv[2];
if (!subjectDid) { process.stderr.write('usage: issue-pathb.mjs <subjectDid>\n'); process.exit(2); }
const passphrase = process.env.HEARTHOLD_PASSPHRASE;

const SCHEMA = {
  $schema: 'http://json-schema.org/draft-07/schema#',
  type: 'object',
  properties: { role: { type: 'string' }, tier: { type: 'string' } },
  required: ['role', 'tier'],
};

const config = loadConfig();
const issuer = await openKeymaster('warden', config, passphrase);
await issuer.keymaster.setCurrentId(IDENTITY_NAME.warden);
const schemaDid = await issuer.keymaster.createSchema(SCHEMA);
const bound = await issuer.keymaster.bindCredential(subjectDid, { schema: schemaDid, claims: { role: 'counterparty', tier: 'verified' } });
const credDid = await issuer.keymaster.issueCredential(bound, { schema: schemaDid });
const issuerDid = (await issuer.keymaster.resolveDID(IDENTITY_NAME.warden)).didDocument.id;
process.stdout.write(JSON.stringify({ credDid, schemaDid, issuerDid }) + '\n');
