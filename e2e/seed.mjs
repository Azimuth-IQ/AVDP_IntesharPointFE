// Idempotent seed for the E2E suite's disposable accounts.
//
// The UAT DB gets wiped periodically, which deletes the agent/store accounts these specs log
// in as. Run this once (with TOTP OFF — see README) to (re)create the hierarchy so the *_PHONE
// defaults in the specs resolve. Safe to re-run: each entity is deleted-then-created.
//
//   BASE_URL=http://34.185.153.95 node e2e/seed.mjs
//
// Requires Node 18+ (global fetch). Assumes HQ 07705371953 / root exists and AUTH_TOTP_ENABLED
// is false on the target backend (login here sends no TOTP code).

const BASE = process.env.BASE_URL || 'http://34.185.153.95';
const HQ_PHONE = process.env.HQ_PHONE || '07705371953';
const HQ_PASS = process.env.HQ_PASS || 'root';
const PASS = process.env.E2E_PASS || 'FMg557ory';

// Kept in sync with the *_PHONE defaults in tests/06,07,08 + 03.
const A1 = { id: 'e2e-agent1', phone: process.env.A1_PHONE || '07960226000', gov: 'BASRA' };
const A2 = { id: 'e2e-agent2', phone: process.env.A2_PHONE || '07959111000' };
const ST = { id: 'e2e-store', admin: process.env.ST_PHONE || '07959222000', pos: process.env.POS_PHONE || '07703333333' };

async function api(path, { method = 'GET', token, body } = {}) {
  const res = await fetch(BASE + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json;
  try { json = JSON.parse(text); } catch { json = { raw: text }; }
  return { status: res.status, json };
}

async function login(phone, password) {
  const { json } = await api('/api/auth/login', { method: 'POST', body: { phone, password } });
  if (json.mustChangePassword) return { mustChange: true };
  return { token: json.token };
}

// New users are created with `Temp1234` then rotated to PASS so the forced-change flag clears.
async function makeUser(phone, role) {
  return { id: `u-${phone}`, phone, password: 'Temp1234', role, capabilities: role === 'ADMIN' ? ['AGENT_ADMIN'] : [] };
}

async function clearRotation(phone) {
  await api('/api/auth/change-password', {
    method: 'POST',
    body: { phone, oldPassword: 'Temp1234', currentPassword: 'Temp1234', newPassword: PASS },
  });
}

async function recreate(hq, entity) {
  await api(`/api/entity/delete?id=${entity.id}`, { method: 'DELETE', token: hq }); // best-effort
  const { status, json } = await api('/api/entity/create', { method: 'POST', token: hq, body: entity.body });
  console.log(`  ${entity.body.type} ${entity.id}: ${status} ${json.message ?? ''}`);
  return status < 300;
}

(async () => {
  const hqLogin = await login(HQ_PHONE, HQ_PASS);
  if (!hqLogin.token) {
    console.error(`HQ login failed (${hqLogin.mustChange ? 'mustChangePassword' : 'no token'}). Is TOTP OFF on ${BASE}?`);
    process.exit(1);
  }
  const hq = hqLogin.token;
  console.log('HQ token OK — seeding hierarchy on', BASE);

  await recreate(hq, { id: A1.id, body: {
    id: A1.id, type: 'AGENT1', parent: 'inteshar-1',
    meta: { name: 'E2E Main Agent', governorates: [A1.gov] },
    users: [await makeUser(A1.phone, 'ADMIN')],
  }});
  await recreate(hq, { id: A2.id, body: {
    id: A2.id, type: 'AGENT2', parent: A1.id,
    meta: { name: 'E2E Sub Agent', governorates: [A1.gov] },
    users: [await makeUser(A2.phone, 'ADMIN')],
  }});
  await recreate(hq, { id: ST.id, body: {
    id: ST.id, type: 'STORE', parent: A2.id,
    meta: { name: 'E2E Store', governorates: [A1.gov] },
    users: [await makeUser(ST.admin, 'ADMIN'), await makeUser(ST.pos, 'USER')],
  }});

  for (const phone of [A1.phone, A2.phone, ST.admin, ST.pos]) {
    await clearRotation(phone);
  }
  console.log(`\nSeeded. Logins (all password '${PASS}'): A1 ${A1.phone}, A2 ${A2.phone}, store-admin ${ST.admin}, POS ${ST.pos}.`);
  console.log('NOTE: spec 03 (POS draw) also needs the pool rebuilt (company + "iCASH 5k IQD" SKU + AVAILABLE');
  console.log('cards in the A1 pool + pricing + a withdrawal grant to the store) + the POS PIN 1111 set on first login.');
})();
