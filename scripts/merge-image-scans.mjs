#!/usr/bin/env node
// Merges per-image osv-scanner JSON outputs into one, prefixing each package name with its image and
// collapsing the binary packages of one source package into a single entry.
//   node scripts/merge-image-scans.mjs <out.json> [<image>=<osv.json>]...
import { readFileSync, writeFileSync } from 'node:fs';

// Keeps only the affected[] entries of the scanned package, which the image prefix would hide from fixedOf.
function ownAffected(v, name, ecosystem) {
  const norm = (n) => String(n ?? '').toLowerCase().replace(/[-_.]+/g, '-');
  const eco = (e) => String(e ?? '').split(':')[0].toLowerCase();
  const mine = (v.affected || []).filter((a) => norm(a.package?.name) === norm(name)
    && (!ecosystem || !a.package?.ecosystem || eco(a.package.ecosystem) === eco(ecosystem)));
  return mine.length ? { ...v, affected: mine } : v;
}

const [out, ...pairs] = process.argv.slice(2);
if (!out) { console.error('usage: merge-image-scans.mjs <out.json> [<image>=<osv.json>]...'); process.exit(2); }

const results = [];
for (const pair of pairs) {
  const at = pair.indexOf('=');
  if (at <= 0) { console.error(`merge-image-scans: invalid argument "${pair}"`); process.exit(2); }
  const image = pair.slice(0, at);
  const src = pair.slice(at + 1);
  let data;
  try { data = JSON.parse(readFileSync(src, 'utf8')); } catch (e) {
    console.error(`merge-image-scans: cannot read "${src}" (${e.code || e.message})`);
    process.exit(1);
  }
  if (!data || !Array.isArray(data.results)) {
    console.error(`merge-image-scans: "${src}" has no "results" array`);
    process.exit(1);
  }
  for (const r of data.results) {
    const byName = new Map();
    for (const p of (r.packages || [])) {
      const name = `${image}/${p.package?.name || '?'}`;
      if (!byName.has(name)) {
        byName.set(name, { ...p, package: { ...(p.package || {}), name }, vulnerabilities: [], groups: [] });
      }
      const merged = byName.get(name);
      const version = p.package?.version || '';
      const versions = String(merged.package.version || '').split(', ').filter(Boolean);
      if (version && !versions.includes(version)) merged.package.version = [...versions, version].join(', ');
      for (const v of (p.vulnerabilities || [])) {
        if (!merged.vulnerabilities.some((x) => x.id === v.id)) merged.vulnerabilities.push(ownAffected(v, p.package?.name, p.package?.ecosystem));
      }
      for (const g of (p.groups || [])) {
        if (!merged.groups.some((x) => JSON.stringify(x.ids) === JSON.stringify(g.ids))) merged.groups.push(g);
      }
    }
    results.push({ ...r, source: { ...(r.source || {}), path: `${image}:${r.source?.path || ''}` }, packages: [...byName.values()] });
  }
}
writeFileSync(out, JSON.stringify({ results }, null, 2) + '\n');
console.log(`Wrote ${out}: ${pairs.length} image(s), ${results.reduce((n, r) => n + r.packages.length, 0)} package(s).`);
