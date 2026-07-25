// aegis sphere SEED — a private hyperdht bootstrap node, bound to a tailnet IP.
// Every sphere member points SM_SEED at this. Because the seed is reached over the tailnet,
// members' reflexive addresses ARE their tailnet IPs, so they connect directly over WireGuard.
// Run this on the stable node (e.g. megaflax), host-networked, bound to its tailnet IP:
//   node seed.mjs 49737 100.81.183.80
import DHT from 'hyperdht';
const port = +(process.argv[2] || process.env.SEED_PORT || 49737);
const host = process.argv[3] || process.env.SEED_HOST;
if (!host) { console.error('usage: node seed.mjs <port> <tailnet-host-ip>'); process.exit(1); }
const node = DHT.bootstrapper(port, host);
node.ready().then(() => console.log(`[aegis-seed] hyperdht bootstrap ready on ${host}:${port}`));
setInterval(() => {}, 1 << 30);
