// Path B core: the subject opens a DmzSession against a PEERLESS DMZ, imports a COUNTERPARTY's
// credential ops there, and verifies the op chain — the subject's OWN gatekeeper is never touched
// (DmzSession binds to dmzNodeUrl, not config.nodeUrl). The "own node never held it" half is
// asserted by the orchestrator against node B's gatekeeper.
import { readFileSync } from 'node:fs';
import { loadConfig, DmzSession } from '@hearthold/core';

const opsOf = (p) => JSON.parse(readFileSync(p, 'utf8'))[0];           // admin export-did -> [[events]]
const issuerOps = opsOf(process.env.ISSUER_OPS);
const schemaOps = opsOf(process.env.SCHEMA_OPS);
const vcOps     = opsOf(process.env.VC_OPS);
const { ISSUER_DID, SCHEMA_DID, VC_DID } = process.env;

const config = loadConfig();
const session = await DmzSession.open({
  dmzNodeUrl: process.env.HEARTHOLD_DMZ_URL,
  role: 'sovereign',
  config,
  passphrase: process.env.HEARTHOLD_PASSPHRASE,
});
console.log(`  DMZ session open against ${session.dmzNodeUrl} (peerless target accepted)`);

await session.import([issuerOps, schemaOps, vcOps], [ISSUER_DID, SCHEMA_DID, VC_DID]);
const vcChain = await session.verifyChain(VC_DID);
const issChain = await session.verifyChain(ISSUER_DID);
console.log(`  verifyChain(vc)     in DMZ : ${vcChain.ok}`);
console.log(`  verifyChain(issuer) in DMZ : ${issChain.ok}`);

session.teardown();
const residue = session.assertNothingSurvives();          // Hearthold-side: the session holds no residue
console.log(`  session teardown: destroyed=${residue.destroyed} residue=${residue.residue.length}`);
process.stdout.write(`RESULT ${vcChain.ok && issChain.ok && residue.destroyed && residue.residue.length === 0 ? 'VERIFIED_IN_DMZ' : 'FAILED'}\n`);
