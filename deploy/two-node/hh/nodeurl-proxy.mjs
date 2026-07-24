// Aegis node-URL proxy: unify a Hearthold subject's single HEARTHOLD_NODE_URL across the isolated
// node's split surfaces, so the UNMODIFIED serve-credential-delivery.ts works.
//
// The subject's keymaster needs BOTH the gatekeeper DB (resolve + admin ops: /dids/import,
// /processEvents) AND the DIDComm relay. On an isolated node those live on two ports, and
// Drawbridge does NOT proxy the admin/DB endpoints (import/processEvents 404 there). So route:
//   /didcomm/*  -> Drawbridge (:4222)  — the DIDComm relay
//   everything  -> raw gatekeeper (:4224), injecting the admin key — resolve + import + processEvents
// Resolve isn't admin-gated (the key is harmless there); import/processEvents require it. The raw
// gatekeeper carries the peer fallback, so cross-node resolution still works.
// This substrate proxy absorbs the HEARTHOLD_GATEKEEPER_URL decoupling Hearthold hasn't wired yet.
import http from 'node:http';
const GK = { host: process.env.GK_HOST || 'gatekeeper-b', port: +(process.env.GK_PORT || 4224) };
const DB = { host: process.env.DB_HOST || 'drawbridge-b', port: +(process.env.DB_PORT || 4222) };
const ADMIN = process.env.ADMIN_KEY || '';
http.createServer((req, res) => {
  const toDidcomm = req.url.startsWith('/didcomm');
  const t = toDidcomm ? DB : GK;
  const headers = { ...req.headers, host: `${t.host}:${t.port}` };
  if (!toDidcomm && ADMIN) headers['x-archon-admin-key'] = ADMIN;   // gatekeeper admin ops
  const up = http.request({ host: t.host, port: t.port, path: req.url, method: req.method, headers },
    r => { res.writeHead(r.statusCode, r.headers); r.pipe(res); });
  up.on('error', e => { res.writeHead(502); res.end(String(e)); });
  req.pipe(up);
}).listen(4299, () => console.log('aegis nodeurl-proxy :4299  /didcomm->%s:%d  else->%s:%d(+admin)', DB.host, DB.port, GK.host, GK.port));
