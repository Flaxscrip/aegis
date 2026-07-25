// Config for the aegis secure mediator. Everything comes from SM_* env vars.
import crypto from 'node:crypto';

function req(name) { const v = process.env[name]; if (!v) throw new Error(`missing required env ${name}`); return v; }
function list(name) { return (process.env[name] || '').split(',').map(s => s.trim()).filter(Boolean); }

export const config = {
  // Archon services (as-is) — talk over their public HTTP API.
  gatekeeperUrl: process.env.SM_GATEKEEPER_URL || 'http://gatekeeper:4224',
  keymasterUrl:  process.env.SM_KEYMASTER_URL  || 'http://keymaster:4226',
  adminKey:      req('SM_ADMIN_KEY'),           // gatekeeper+keymaster admin key (batch import/sign are admin-gated)

  // This node's mediator identity — a keymaster id (name) whose DID signs the auth handshake.
  nodeName:      req('SM_NODE_NAME'),

  // Sphere transport.
  protocol:      req('SM_PROTOCOL'),            // shared sphere string -> sha256 -> topic
  seed:          req('SM_SEED'),                // host:port of the hyperdht bootstrapper (the stable seed)
  bind:          process.env.SM_BIND || undefined,   // own tailnet IP to bind (required for firewalled:false)

  // SECURITY — peer auth allowlist (member node DIDs) + gossip scope (DIDs allowed to cross).
  members:       list('SM_MEMBERS'),            // only peers proving one of these DIDs may join
  shareDids:     list('SM_SHARE_DIDS'),         // the ONLY DIDs exported out and accepted in (scope)

  exportInterval: +(process.env.SM_EXPORT_INTERVAL || 15),

  get topic() { return crypto.createHash('sha256').update(this.protocol).digest(); },
  get bootstrap() { const [h, p] = this.seed.split(':'); return [{ host: h, port: +p }]; },
};
