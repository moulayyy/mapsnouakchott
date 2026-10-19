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

// ---- blocs (îlots) : lots voisins reliés entre eux ; la rue sépare les blocs.
// Retourne les blocs du plan et ajoute le n° de bloc en position 7 de chaque ligne.
function clusterBlocks(lots, planIdx) {
  const par = lots.map((_, i) => i);
  const find = (x) => {
    while (par[x] !== x) {
      par[x] = par[par[x]];
      x = par[x];
    }
    return x;
  };
  const union = (a, b) => {
    a = find(a);
    b = find(b);
    if (a !== b) par[a] = b;
  };
  const kx = 111320 * Math.cos((lots[0][6][1] * Math.PI) / 180);
  const ky = 110574;
  const CELL = 3;
  const TOL = 2.0;
  const STEP = 2.0;
  const grid = new Map();
  const addPoint = (i, x, y) => {
    const cx = Math.floor(x / CELL);
    const cy = Math.floor(y / CELL);
    for (let dx = -1; dx <= 1; dx++) {
      for (let dy = -1; dy <= 1; dy++) {
        const arr = grid.get(`${cx + dx},${cy + dy}`);
        if (!arr) continue;
        for (let k = 0; k < arr.length; k += 3) {
          if (arr[k] !== i && Math.hypot(x - arr[k + 1], y - arr[k + 2]) < TOL) union(i, arr[k]);
        }
      }
    }
    const key = `${cx},${cy}`;
    if (!grid.has(key)) grid.set(key, []);
    grid.get(key).push(i, x, y);
  };
  const lotIdx = [];
  lots.forEach((l, i) => {
    if (l[2] !== 0) return;
    lotIdx.push(i);
    const ring = l[6];
    const n = ring.length / 2;
    for (let k = 0; k < n; k++) {
      const x1 = ring[2 * k] * kx, y1 = ring[2 * k + 1] * ky;
      const x2 = ring[2 * ((k + 1) % n)] * kx, y2 = ring[2 * ((k + 1) % n) + 1] * ky;
      const steps = Math.max(1, Math.ceil(Math.hypot(x2 - x1, y2 - y1) / STEP));
      for (let s = 0; s < steps; s++) {
        addPoint(i, x1 + ((x2 - x1) * s) / steps, y1 + ((y2 - y1) * s) / steps);
      }
    }
  });
  const groups = new Map();
  for (const i of lotIdx) {
    const r = find(i);
    if (!groups.has(r)) groups.set(r, []);
    groups.get(r).push(i);
  }
  const num = (l) => (/^\d+$/.test(l[1] ?? '') ? parseInt(l[1], 10) : null);
  const list = [...groups.values()].map((g) => {
    const nums = g.map((i) => num(lots[i])).filter((v) => v !== null);
    const lat = g.reduce((s, i) => s + lots[i][6][1], 0) / g.length;
    return { g, lo: nums.length ? Math.min(...nums) : null, hi: nums.length ? Math.max(...nums) : null, lat };
  });
  list.sort((a, b) => {
    if (a.lo !== null && b.lo !== null) return a.lo - b.lo;
    if (a.lo !== null) return -1;
    if (b.lo !== null) return 1;
    return b.lat - a.lat;
  });
  const out = [];
  lots.forEach((l) => (l[7] = null));
  list.forEach((b, k) => {
    const n = k + 1;
    const pts = [];
    for (const i of b.g) {
      lots[i][7] = n;
      const r = lots[i][6];
      for (let q = 0; q + 1 < r.length; q += 2) pts.push([r[q], r[q + 1]]);
    }
    out.push([planIdx, n, b.g.length, b.lo, b.hi, hull(pts)]);
  });
  return out;
}

function hull(points) {
  const p = [...new Set(points.map((q) => q.join(',')))].map((s) => s.split(',').map(Number));
  p.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  if (p.length < 3) return p.flat();
  const cross = (o, a, b) => (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);
  const lower = [];
  for (const q of p) {
    while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], q) <= 0) lower.pop();
    lower.push(q);
  }
  const upper = [];
  for (let i = p.length - 1; i >= 0; i--) {
    const q = p[i];
    while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], q) <= 0) upper.pop();
    upper.push(q);
  }
  upper.pop();
  lower.pop();
  return lower.concat(upper).flat();
}

const geoDocs = []; // {id, data:{plan,n,j}, keys:[...]}
const blocks = [];
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
  const planBlocks = clusterBlocks(lots, planIdx); // ajoute le n° de bloc en [7]
  blocks.push(...planBlocks);
  const sizes = planBlocks.map((b) => b[2]).sort((a, b) => a - b);
  console.log(
    `plan ${planIdx} ${plans[planIdx]?.name}: ${lots.length} lignes, ${planBlocks.length} blocs, ` +
      `taille médiane ${sizes[Math.floor(sizes.length / 2)] ?? 0}, max ${sizes[sizes.length - 1] ?? 0}, isolés ${sizes.filter((s) => s === 1).length}`
  );
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
  { id: 'blocks', data: { j: JSON.stringify(blocks) } },
];
if (metaDocs.find((d) => d.id === 'blocks').data.j.length > 900_000) throw new Error('doc blocs trop gros');

// ---- parcelles et îlots ESTIMÉS (estimation d'après rues et bâti, sans valeur juridique)
// Îlot : [id, m, tier, module, src, nb, area, regular, first, last, galt, quartier, lts, mCorr, inCert, ring]
const estBlockRows = rd('blocks.json');
const certBlockIds = new Set(estBlockRows.filter((b) => b[15]).map((b) => b[0]));
const estBlocksSorted = [...estBlockRows].sort((a, b) => a[0] - b[0]);
const estDocs = []; // {col, id, data}
for (let i = 0; i * 1000 < estBlocksSorted.length; i++) {
  const rows = estBlocksSorted.slice(i * 1000, (i + 1) * 1000).map((b) => [
    b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[11], b[12], b[13], b[14], b[15], b[16],
  ]);
  const j = JSON.stringify(rows);
  if (j.length > 900_000) throw new Error(`chunk d'îlots trop gros: ${i}`);
  estDocs.push({ col: 'est_blocks', id: `b${i}`, data: { j } });
}
// Parcelles : tuiles de 0,005° ; origine = coin sud-ouest, anneaux en micro-degrés (comme le prototype)
const [aoiW, aoiS] = meta.aoi;
const tileKeys = [];
let estLotCount = 0;
let estLotSkipped = 0;
for (const f of fs.readdirSync(path.join(dir, 'lots')).filter((n) => n.endsWith('.json')).sort()) {
  const key = f.replace('.json', '');
  const [ix, iy] = key.split('_').map(Number);
  const rows = JSON.parse(fs.readFileSync(path.join(dir, 'lots', f), 'utf8')).filter((r) => {
    if (certBlockIds.has(r[1])) {
      estLotSkipped++;
      return false; // remplacé par les lots certifiés
    }
    return true;
  });
  if (rows.length === 0) continue;
  const j = JSON.stringify(rows);
  if (j.length > 900_000) throw new Error(`tuile trop grosse: ${key}`);
  estLotCount += rows.length;
  tileKeys.push(key);
  estDocs.push({
    col: 'est_lots',
    id: key,
    data: {
      ox: Math.round((aoiW + ix * meta.tile_deg) * 1e6) / 1e6,
      oy: Math.round((aoiS + iy * meta.tile_deg) * 1e6) / 1e6,
      j,
    },
  });
}
estDocs.push({
  col: 'meta',
  id: 'est',
  data: {
    j: JSON.stringify({
      aoi: meta.aoi,
      tileDeg: meta.tile_deg,
      tiles: tileKeys,
      streetNames: meta.street_names,
      streetClasses: meta.street_classes,
      quartiers: meta.quartiers,
      poi: meta.poi_categories,
    }),
  },
});
console.log(
  `Estimés: ${estBlockRows.length} îlots (${certBlockIds.size} dans le certifié, non dessinés), ` +
    `${estLotCount} parcelles dans ${tileKeys.length} tuiles (${estLotSkipped} ignorées car dans un îlot certifié)`
);

console.log(`Plans: ${plans.length} | lotissements: ${lotissements.length} | lots (avec contour): ${totalLots}`);
console.log(`Documents geo: ${geoDocs.length} | taille totale: ${(geoDocs.reduce((s, d) => s + d.data.j.length, 0) / 1e6).toFixed(2)} Mo`);

if (dry) {
  fs.mkdirSync('out', { recursive: true });
  for (const d of metaDocs) fs.writeFileSync(`out/meta_${d.id}.json`, JSON.stringify(d.data));
  for (const d of geoDocs) fs.writeFileSync(`out/geo_${d.id}.json`, JSON.stringify(d.data));
  for (const d of estDocs.filter((x) => x.col === 'est_blocks' || x.id === 'est')) {
    fs.writeFileSync(`out/${d.col}_${d.id}.json`, JSON.stringify(d.data));
  }
  for (const d of estDocs.filter((x) => x.col === 'est_lots').slice(0, 6)) {
    fs.writeFileSync(`out/est_lots_${d.id}.json`, JSON.stringify(d.data));
  }
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

// parcelles et îlots estimés
for (const d of estDocs) {
  await put(db.collection(d.col).doc(d.id), d.data, JSON.stringify(d.data).length);
}
await flush();

// supprime les anciens documents devenus inutiles
for (const col of ['est_blocks', 'est_lots']) {
  const keep = new Set(estDocs.filter((d) => d.col === col).map((d) => d.id));
  for (const doc of (await db.collection(col).get()).docs) {
    if (!keep.has(doc.id)) await doc.ref.delete();
  }
}
const ids = new Set(geoDocs.map((d) => d.id));
for (const col of ['geo_all', 'geo_public']) {
  for (const doc of (await db.collection(col).get()).docs) {
    if (!ids.has(doc.id)) await doc.ref.delete();
  }
}
console.log('Import terminé.');
