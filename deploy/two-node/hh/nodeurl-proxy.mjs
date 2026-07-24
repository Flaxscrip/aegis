// Aegis node-URL proxy: unify a Hearthold subject's single HEARTHOLD_NODE_URL across the isolated
// node's split surfaces, so the UNMODIFIED serve-credential-delivery.ts works. Routes:
//   /api/v1/dids/import  -> raw gatekeeper (:4224), injecting the admin key (import is admin-gated
//                           and NOT proxied by drawbridge)
//   everything else      -> drawbridge (:4222) (gatekeeper API, /dids, /dids/export, /didcomm, ...)
// This is the substrate absorbing the HEARTHOLD_GATEKEEPER_URL decoupling Hearthold hasn't wired yet.
import http from 'node:http';
const GK = { host: process.env.GK_HOST || 'gatekeeper-b', port: +(process.env.GK_PORT || 4224) };
const DB = { host: process.env.DB_HOST || 'drawbridge-b', port: +(process.env.DB_PORT || 4222) };
const ADMIN = process.env.ADMIN_KEY || '';
http.createServer((req, res) => {
  const toGk = req.url.startsWith('/api/v1/dids/import');
  const t = toGk ? GK : DB;
  const headers = { ...req.headers, host: `${t.host}:${t.port}` };
  if (toGk && ADMIN) headers['x-archon-admin-key'] = ADMIN;
  const up = http.request({ host: t.host, port: t.port, path: req.url, method: req.method, headers },
    r => { res.writeHead(r.statusCode, r.headers); r.pipe(res); });
  up.on('error', e => { res.writeHead(502); res.end(String(e)); });
  req.pipe(up);
}).listen(4299, () => console.log('aegis nodeurl-proxy :4299  import->%s:%d  else->%s:%d', GK.host, GK.port, DB.host, DB.port));
