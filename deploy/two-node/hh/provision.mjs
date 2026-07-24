// Aegis glue: ensure a Hearthold role identity exists in this wallet, print its DID.
//   node deploy/two-node/hh/provision.mjs <role>            (role: warden | sovereign | ...)
// Runs INSIDE a hearthold:sandbox container (resolves @hearthold/core from /app/node_modules).
// Config from env: HEARTHOLD_NODE_URL, HEARTHOLD_REGISTRY, HEARTHOLD_DATA_ROOT, HEARTHOLD_PASSPHRASE.
import { loadConfig, openKeymaster, ensureIdentity, IDENTITY_NAME } from '@hearthold/core';

const role = process.argv[2];
if (!role) { process.stderr.write('usage: provision.mjs <role>\n'); process.exit(2); }
const passphrase = process.env.HEARTHOLD_PASSPHRASE;
if (!passphrase) throw new Error('HEARTHOLD_PASSPHRASE is required');

const config = loadConfig();
const handle = await openKeymaster(role, config, passphrase);
await ensureIdentity(handle, config);
const name = IDENTITY_NAME[role];
const doc = await handle.keymaster.resolveDID(name);
process.stdout.write(`${doc.didDocument.id}\n`);
