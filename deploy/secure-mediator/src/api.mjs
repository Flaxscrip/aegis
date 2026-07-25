// Thin fetch wrapper over an Archon service's public HTTP API (gatekeeper or keymaster).
// Uses the admin header for the admin-gated routes (batch import/export, keys/sign).
export function api(baseUrl, adminKey) {
  const headers = { 'content-type': 'application/json', 'x-archon-admin-key': adminKey };
  async function call(method, path, body) {
    const res = await fetch(baseUrl + '/api/v1' + path, {
      method, headers, body: body !== undefined ? JSON.stringify(body) : undefined,
    });
    const txt = await res.text();
    let data; try { data = JSON.parse(txt); } catch { data = txt; }
    if (!res.ok) throw new Error(`${method} ${path} -> ${res.status}: ${String(txt).slice(0, 180)}`);
    return data;
  }
  return {
    call,
    ready: async () => { try { const r = await call('GET', '/ready'); return r === true || r === 'true' || r?.ready === true; } catch { return false; } },
  };
}
