#!/usr/bin/env node
// Import HADDOU_MAP -> Firestore (projet maps-fea5f).
// Usage : node import.mjs <dossier webmap/data> [--dry]
//   --dry : n'écrit rien dans Firestore, génère ./out/*.json pour inspection.
// Identifiants : GOOGLE_APPLICATION_CREDENTIALS=<clé compte de service>
//   ou `gcloud auth application-default login`.
import fs from 'node:fs';
import path from 'node:path';

const args = process.argv.slice(2);
const dir = args.find((a) => !a.startsWith('--'));
const dry = args.includes('--dry');
const PROJECT_ID = 'maps-fea5f';
const CHUNK = 500; // lots par document

if (!dir) {
  console.error('Usage: node import.mjs <dossier webmap/data> [--dry]');
  process.exit(1);
}
const rd = (f) => JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
const meta = rd('meta.json');
const cert = rd('certified.json');
const lts = rd('lotissements.json');

const moughataas = meta.moughataas;
const mCode = Object.fromEntries(moughataas.map((m) => [m.fr, m.code]));
const kinds = meta.certified_kinds;
const planDefs = meta.certified_plans;

// ---- plans
const plans = planDefs.map((p, idx) => ({
  idx,
  plan: p.plan,
  name: p.lotissement,
  ltsId: p.lts_id,
  m: mCode[p.moughataa] ?? -1,
  n: p.n_lots,
  acc: p.georef_accuracy_m ?? null,
  partial: !!p.partial,
  b: p.bounds,
}));
const planByLts = Object.fromEntries(plans.map((p) => [p.ltsId, p.idx]));

// ---- lotissements : [id, name, m, planLots, lat, lon, planIdx|-1]
const lotissements = lts.map((t) => [
  t[0], t[1], t[2], t[3], t[4], t[5], planByLts[t[0]] ?? -1,
]);

// ---- lots certifiés groupés par plan
const sanitize = (s) => String(s).replace(/[^A-Za-z0-9_-]/g, '-');
const byPlan = new Map();
cert.forEach((r, i) => {
  const ring = r[4];
  if (!ring || ring.length < 6) return;
  const planIdx = r[3];
  if (!byPlan.has(planIdx)) byPlan.set(planIdx, []);
  byPlan.get(planIdx).push({ r, i });
});

const geoDocs = []; // {id, data:{plan,n,j}, keys:[...]}
let totalLots = 0;
for (const [planIdx, rows] of [...byPlan.entries()].sort((a, b) => a[0] - b[0])) {
  const used = new Set();
  const lots = rows.map(({ r, i }) => {
    let base = r[0] != null && r[0] !== '' ? `c${planIdx}_${sanitize(r[0])}` : `c${planIdx}_e${i}`;
    let key = base;
    let n = 2;
    while (used.has(key)) key = `${base}_${n++}`;
    used.add(key);
    const label = r[0] != null && r[0] !== '' ? String(r[0]) : null;
    // [key,label,kind,area,status,name,ring]
    return [key, label, r[1], r[2], r[7] ?? null, r[6] ?? null, r[4]];
  });
  totalLots += lots.length;
  for (let c = 0; c * CHUNK < lots.length; c++) {
    const slice = lots.slice(c * CHUNK, (c + 1) * CHUNK);
    const j = JSON.stringify(slice);
    if (j.length > 900_000) throw new Error(`chunk trop gros: p${planIdx}_${c}`);
    geoDocs.push({ id: `p${planIdx}_${c}`, data: { plan: planIdx, n: c, j }, keys: slice.map((x) => x[0]) });
  }
}

const metaDocs = [
  { id: 'moughataas', data: { j: JSON.stringify(moughataas.map((m) => ({ code: m.code, fr: m.fr, ar: m.ar }))) } },
  { id: 'plans', data: { j: JSON.stringify(plans), kinds } },
  { id: 'lotissements', data: { j: JSON.stringify(lotissements) } },
];

console.log(`Plans: ${plans.length} | lotissements: ${lotissements.length} | lots (avec contour): ${totalLots}`);
console.log(`Documents geo: ${geoDocs.length} | taille totale: ${(geoDocs.reduce((s, d) => s + d.data.j.length, 0) / 1e6).toFixed(2)} Mo`);

if (dry) {
  fs.mkdirSync('out', { recursive: true });
  for (const d of metaDocs) fs.writeFileSync(`out/meta_${d.id}.json`, JSON.stringify(d.data));
  for (const d of geoDocs) fs.writeFileSync(`out/geo_${d.id}.json`, JSON.stringify(d.data));
  console.log('Mode --dry : fichiers écrits dans ./out, rien envoyé.');
  process.exit(0);
}

const { initializeApp, applicationDefault } = await import('firebase-admin/app');
const { getFirestore } = await import('firebase-admin/firestore');
initializeApp({ credential: applicationDefault(), projectId: PROJECT_ID });
const db = getFirestore();

// lots désactivés par l'admin : à ne pas republier
const off = new Set((await db.collection('lots').where('active', '==', false).get()).docs.map((d) => d.id));
console.log(`Lots désactivés conservés hors de geo_public: ${off.size}`);

let batch = db.batch();
let ops = 0;
let bytes = 0;
const flush = async () => {
  if (ops === 0) return;
  await batch.commit();
  batch = db.batch();
  ops = 0;
  bytes = 0;
};
const put = async (ref, data, size) => {
  if (ops >= 100 || bytes + size > 4_000_000) await flush();
  batch.set(ref, data);
  ops++;
  bytes += size;
};

for (const d of metaDocs) await put(db.collection('meta').doc(d.id), d.data, JSON.stringify(d.data).length);
for (const d of geoDocs) {
  await put(db.collection('geo_all').doc(d.id), d.data, d.data.j.length);
  let pub = d.data;
  if (d.keys.some((k) => off.has(k))) {
    const rows = JSON.parse(d.data.j).filter((x) => !off.has(x[0]));
    pub = { ...d.data, j: JSON.stringify(rows) };
  }
  await put(db.collection('geo_public').doc(d.id), pub, pub.j.length);
}
await flush();

// supprime les anciens documents devenus inutiles
const ids = new Set(geoDocs.map((d) => d.id));
for (const col of ['geo_all', 'geo_public']) {
  for (const doc of (await db.collection(col).get()).docs) {
    if (!ids.has(doc.id)) await doc.ref.delete();
  }
}
console.log('Import terminé.');
