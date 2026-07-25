// aegis-secure-mediator — a hardened hyperswarm mediator for Archon spheres.
//
// Three properties the stock mediator lacks:
//   1. TAILNET TRANSPORT  — private hyperdht (bootstrap=seed, bind=own tailnet IP, firewalled:false):
//                           connects directly over WireGuard, no public DHT, no holepunch. Stable, no churn.
//   2. PEER AUTH          — a peer may join only by proving control of an allowlisted member node DID
//                           (challenge -> keymaster addProof -> verifyProof + allowlist + fresh nonce).
//   3. SCOPED GOSSIP      — only SM_SHARE_DIDS are exported out AND accepted in. Anything else is dropped,
//                           so a member's private (local-registry) DIDs are structurally un-gossipable.
//
// Uses Archon AS-IS: every gatekeeper/keymaster call is the public HTTP API. No core changes.
import Hyperswarm from 'hyperswarm';
import DHT from 'hyperdht';
import b4a from 'b4a';
import crypto from 'node:crypto';
import { config } from './config.mjs';
import { api } from './api.mjs';

const gk = api(config.gatekeeperUrl, config.adminKey);
const km = api(config.keymasterUrl, config.adminKey);
const sleep = ms => new Promise(r => setTimeout(r, ms));
const log = (...a) => console.log(new Date().toISOString(), ...a);
const topicHex = b4a.toString(config.topic, 'hex');

let myDID = null;
const authed = new Map();   // conn -> { did }
const myNonce = new Map();  // conn -> nonce I issued (challenge)

async function waitReady(name, a) {
  for (let i = 0; i < 120; i++) { if (await a.ready()) { log(`${name} ready`); return; } log(`waiting for ${name}...`); await sleep(3000); }
  throw new Error(`${name} never became ready`);
}

async function main() {
  await waitReady('gatekeeper', gk);
  await waitReady('keymaster', km);

  // Select the signing identity (keys/sign signs as the current id).
  await km.call('PUT', '/ids/current', { name: config.nodeName });
  const idres = await km.call('GET', `/ids/${encodeURIComponent(config.nodeName)}`);
  myDID = idres?.docs?.didDocument?.id || idres?.didDocument?.id;
  if (!myDID) throw new Error(`could not resolve node identity '${config.nodeName}'`);
  log(`identity: ${config.nodeName} = ${myDID}`);
  log(`members allowlist (${config.members.length}): ${config.members.join(', ') || '(NONE — no peer can auth!)'}`);
  log(`gossip scope (${config.shareDids.length} DIDs): ${config.shareDids.join(', ') || '(NONE — nothing will sync)'}`);
  if (!config.members.includes(myDID)) log(`NOTE: my DID is not in SM_MEMBERS; peers must include it in theirs to accept me.`);

  const dht = new DHT({ bootstrap: config.bootstrap, host: config.bind, firewalled: false });
  const swarm = new Hyperswarm({ dht });
  swarm.on('connection', onConnection);
  const disc = swarm.join(config.topic, { client: true, server: true });
  await disc.flushed();
  log(`joined sphere topic ${topicHex.slice(0, 12)} seed=${config.seed} bind=${config.bind || 'ALL'} firewalled=false`);

  setInterval(exportLoop, config.exportInterval * 1000);
}

function send(conn, obj) { try { conn.write(Buffer.from(JSON.stringify(obj) + '\n')); } catch {} }

function onConnection(conn) {
  const remote = b4a.toString(conn.remotePublicKey, 'hex').slice(0, 8);
  log(`connection remote=${remote} — authenticating`);
  conn.on('error', () => {});
  conn.on('close', () => { authed.delete(conn); myNonce.delete(conn); log(`closed remote=${remote}`); });

  let buf = '';
  conn.on('data', d => {
    buf += d.toString();
    let i;
    while ((i = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, i); buf = buf.slice(i + 1);
      handleMsg(conn, remote, line).catch(e => log('msg error', e.message));
    }
  });

  // open the handshake: issue our challenge nonce
  const nonce = crypto.randomUUID();
  myNonce.set(conn, nonce);
  send(conn, { type: 'nonce', nonce });
}

async function handleMsg(conn, remote, line) {
  let msg; try { msg = JSON.parse(line); } catch { return; }

  if (msg.type === 'nonce') {
    // sign the peer's challenge, binding our DID + this sphere topic
    const payload = { t: 'aegis-sphere-auth/v1', nonce: msg.nonce, did: myDID, topic: topicHex };
    const { signed } = await km.call('POST', '/keys/sign', { contents: JSON.stringify(payload) });
    send(conn, { type: 'auth', signed });
    return;
  }

  if (msg.type === 'auth') {
    const signed = msg.signed || {};
    const signer = signed?.proof?.verificationMethod?.split('#')[0];
    let proofOk = false;
    try { proofOk = !!(await km.call('POST', '/keys/verify', { json: signed })).ok; } catch (e) { log('verify error', e.message); }
    const nonceOk = signed.nonce === myNonce.get(conn);           // fresh -> no replay
    const topicOk = signed.topic === topicHex;                    // same sphere
    const memberOk = signer && config.members.includes(signer);   // allowlisted member
    if (proofOk && nonceOk && topicOk && memberOk) {
      authed.set(conn, { did: signer });
      log(`AUTH OK  peer=${signer} remote=${remote}`);
      await pushBatch(conn);                                       // sync immediately
    } else {
      log(`AUTH REJECT remote=${remote} proof=${proofOk} nonce=${nonceOk} topic=${topicOk} member=${memberOk} signer=${signer}`);
      conn.destroy();
    }
    return;
  }

  if (msg.type === 'batch') {
    const who = authed.get(conn);
    if (!who) { log(`drop batch from UNAUTH remote=${remote}`); return; }
    await importScoped(msg.events, who.did);
    return;
  }
}

async function currentBatch() {
  if (!config.shareDids.length) return [];
  try {
    const events = await gk.call('POST', '/batch/export', { dids: config.shareDids });
    return Array.isArray(events) ? events : [];
  } catch (e) { log('export error', e.message); return []; }
}

async function pushBatch(conn) {
  const events = await currentBatch();
  if (events.length) send(conn, { type: 'batch', events });
}

async function exportLoop() {
  const peers = [...authed.keys()];
  if (!peers.length) return;
  const events = await currentBatch();
  if (!events.length) return;
  for (const conn of peers) send(conn, { type: 'batch', events });
  log(`gossiped ${events.length} scoped events -> ${peers.length} authed peer(s)`);
}

async function importScoped(events, fromDID) {
  if (!Array.isArray(events) || !events.length) return;
  const scope = new Set(config.shareDids);
  // Defense-in-depth: accept ONLY events whose target DID is in-scope, even from an authed peer.
  const kept = events.filter(e => scope.has(e.did));
  const dropped = events.length - kept.length;
  if (!kept.length) { if (dropped) log(`dropped ${dropped} out-of-scope events from ${fromDID}`); return; }
  try {
    const res = await gk.call('POST', '/batch/import', kept);
    log(`imported ${kept.length} scoped events from ${fromDID}${dropped ? ` (${dropped} out-of-scope dropped)` : ''} -> ${JSON.stringify(res).slice(0, 90)}`);
  } catch (e) { log('import error', e.message); }
}

main().catch(e => { console.error('fatal', e); process.exit(1); });
