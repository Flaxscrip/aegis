// Aegis glue: issuer (warden) mints a membership VC for a subject DID, prints the credential DID.
//   node deploy/two-node/hh/issue.mjs <subjectDid>
// Runs INSIDE a hearthold:sandbox container on the ISSUER node. Mirrors Hearthold's
// e2e-credential-delivery.ts issuance (createSchema -> bindCredential -> issueCredential as warden).
import { loadConfig, openKeymaster, IDENTITY_NAME } from '@hearthold/core';

const subjectDid = process.argv[2];
if (!subjectDid) { process.stderr.write('usage: issue.mjs <subjectDid>\n'); process.exit(2); }
const passphrase = process.env.HEARTHOLD_PASSPHRASE;
if (!passphrase) throw new Error('HEARTHOLD_PASSPHRASE is required');

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
const bound = await issuer.keymaster.bindCredential(subjectDid, {
  schema: schemaDid,
  claims: { role: 'member', tier: 'verified' },
});
const credDid = await issuer.keymaster.issueCredential(bound, { schema: schemaDid });
process.stdout.write(`${credDid}\n`);
