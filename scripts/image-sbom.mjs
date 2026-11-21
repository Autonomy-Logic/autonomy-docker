#!/usr/bin/env node
// Turns the cdxgen BOM of one image into the release SBOM of that image.
//   node scripts/image-sbom.mjs --in <cdx.json> --out <cdx.json> --dir <image-dir> --name <package>
//     --version <tag> --ref <image-ref> --copyright <dir> --installed <dpkg-list> [--components <json>]
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join } from 'node:path';
import { refOf } from './lib/cdx.mjs';

// Debian short licence names that differ from their SPDX identifier.
const DEBIAN_TO_SPDX = {
  'gpl-1': 'GPL-1.0-only', 'gpl-1+': 'GPL-1.0-or-later', 'gpl-2': 'GPL-2.0-only', 'gpl-2+': 'GPL-2.0-or-later',
  'gpl-3': 'GPL-3.0-only', 'gpl-3+': 'GPL-3.0-or-later', 'gplv2': 'GPL-2.0-only', 'gplv2+': 'GPL-2.0-or-later',
  'gplv3': 'GPL-3.0-only', 'gplv3+': 'GPL-3.0-or-later',
  'lgpl-2': 'LGPL-2.0-only', 'lgpl-2+': 'LGPL-2.0-or-later', 'lgpl-2.1': 'LGPL-2.1-only', 'lgpl-2.1+': 'LGPL-2.1-or-later',
  'lgplv2.1+': 'LGPL-2.1-or-later', 'lgpl-3': 'LGPL-3.0-only', 'lgpl-3+': 'LGPL-3.0-or-later', 'lgplv3+': 'LGPL-3.0-or-later',
  'gfdl-1.2+': 'GFDL-1.2-or-later', 'gfdl-1.3+': 'GFDL-1.3-or-later', 'gfdl-niv-1.3+': 'GFDL-1.3-no-invariants-or-later',
  'bsd-2-clause': 'BSD-2-Clause', 'bsd-3-clause': 'BSD-3-Clause', 'bsd-4-clause': 'BSD-4-Clause',
  'bsd-4-clause-uc': 'BSD-4-Clause-UC', 'bsd-3-clause-attribution': 'BSD-3-Clause-Attribution',
  expat: 'MIT', mit: 'MIT', isc: 'ISC', zlib: 'Zlib', 'apache-2.0': 'Apache-2.0', 'cc0-1.0': 'CC0-1.0', '0bsd': '0BSD',
  curl: 'curl', fsfap: 'FSFAP', fsful: 'FSFUL', fsfullr: 'FSFULLR', x11: 'X11', 'openldap-2.8': 'OLDAP-2.8',
  'unicode-dfs-2016': 'Unicode-DFS-2016', 'mpl-1.1': 'MPL-1.1', 'mpl-2.0': 'MPL-2.0', 'artistic-2.0': 'Artistic-2.0',
  'psf-2': 'PSF-2.0', 'psf-2.0': 'PSF-2.0', 'bsl-1.0': 'BSL-1.0', openssl: 'OpenSSL', beerware: 'Beerware',
  'sleepycat': 'Sleepycat', 'ofl-1.1': 'OFL-1.1', 'cc-by-4.0': 'CC-BY-4.0', 'cc-by-sa-4.0': 'CC-BY-SA-4.0',
  'gpl-2.0-only': 'GPL-2.0-only', 'gpl-2.0-or-later': 'GPL-2.0-or-later', 'lgpl-2.1-or-later': 'LGPL-2.1-or-later',
  'gpl-3.0-or-later': 'GPL-3.0-or-later', 'lgpl-3.0-or-later': 'LGPL-3.0-or-later', 'bsd-3-clause-lbnl': 'BSD-3-Clause-LBNL',
};

const args = Object.fromEntries(process.argv.slice(2).reduce((a, v, i, arr) => {
  if (v.startsWith('--')) a.push([v.slice(2), arr[i + 1]]);
  return a;
}, []));
for (const k of ['in', 'out', 'dir', 'name', 'version', 'ref', 'copyright', 'installed']) {
  if (!args[k]) { console.error(`image-sbom: --${k} is required`); process.exit(2); }
}

// Licence names of the License fields of a machine-readable Debian copyright file, or null.
function debianLicenses(text) {
  if (!/^Format:/m.test(text.split('\n', 1)[0] || '')) return null;
  const names = new Set();
  for (const m of text.matchAll(/^License:[ \t]*(\S[^\n]*)$/gim)) names.add(m[1].trim());
  return [...names];
}

// SPDX expression of one Debian License field, or null when a name has no SPDX identifier.
function toSpdx(field) {
  if (field.includes(',') && /\band\b/i.test(field) && /\bor\b/i.test(field)) return null;
  const tokens = field.split(/\s*(?:,\s*)?\b(and|or)\b\s*/i).filter((t) => t !== '');
  const out = [];
  for (const t of tokens) {
    if (/^(and|or)$/i.test(t)) { out.push(t.toUpperCase()); continue; }
    const id = DEBIAN_TO_SPDX[t.toLowerCase()];
    if (!id) return null;
    out.push(id);
  }
  return out.join(' ');
}

// CycloneDX licences of a package from its copyright file: one SPDX expression, or the raw names.
function licensesOf(pkg) {
  const file = join(args.copyright, pkg, 'copyright');
  if (!existsSync(file)) return [];
  const fields = debianLicenses(readFileSync(file, 'utf8'));
  if (!fields || !fields.length) return [];
  const spdx = fields.map(toSpdx);
  if (spdx.some((e) => !e)) return fields.map((name) => ({ license: { name } }));
  const parts = [...new Set(spdx)];
  if (parts.length === 1 && !/ /.test(parts[0])) return [{ license: { id: parts[0] } }];
  return [{ expression: parts.map((p) => (/ /.test(p) && parts.length > 1 ? `(${p})` : p)).join(' AND ') }];
}

// CycloneDX supplier of a Debian package from its dpkg Maintainer field ("Name <email>").
function maintainerSupplier(maintainer) {
  const m = String(maintainer || '').match(/^\s*(.*?)\s*(?:<([^>]*)>)?\s*$/);
  if (!m || !m[1]) return undefined;
  return { name: m[1], ...(m[2] ? { contact: [{ email: m[2] }] } : {}) };
}

const bom = JSON.parse(readFileSync(args.in, 'utf8'));
const oldRoot = bom.metadata?.component?.['bom-ref'];
// dpkg-query lines: package, version, architecture, maintainer, tab separated.
const installed = new Map(readFileSync(args.installed, 'utf8').split('\n').filter((l) => l.trim())
  .map((l) => { const [name, version, arch, maintainer] = l.split('\t'); return [name, { version, arch, maintainer }]; }));
const isDeb = (c) => String(c.purl || '').startsWith('pkg:deb/');
const keep = (c) => (isDeb(c) ? installed.has(c.name) : !(c.type === 'file' && String(c.purl || '').startsWith('pkg:generic/')));
const components = (bom.components || []).filter(keep);
const distro = (components.find(isDeb)?.purl || '').match(/[?&](distro=[^&]+&distro_name=[^&]+)/)?.[1];
const added = [];
for (const [name, d] of installed) {
  if (components.some((c) => isDeb(c) && c.name === name)) continue;
  const epoch = d.version.includes(':') ? `&epoch=${d.version.split(':')[0]}` : '';
  const purl = `pkg:deb/debian/${encodeURIComponent(name)}@${encodeURIComponent(d.version).replace(/%3A/g, ':')}`
    + `?arch=${d.arch}${distro ? `&${distro}` : ''}${epoch}`;
  components.push({
    'bom-ref': purl, type: 'library', name, version: d.version, purl, group: 'debian',
    ...(maintainerSupplier(d.maintainer) ? { supplier: maintainerSupplier(d.maintainer) } : {}),
    properties: [{ name: 'autonomy:inventory', value: 'dpkg-status' }],
  });
  added.push(purl);
}
if (added.length) console.log(`image-sbom: added from the dpkg database (not reported by cdxgen): ${added.join(' ')}`);
for (const c of components) {
  if (c.tags) c.tags = c.tags.filter((t) => t !== 'source');
  if (c.tags && !c.tags.length) delete c.tags;
  if (isDeb(c) && !c.supplier && !c.manufacturer && !c.publisher) {
    const supplier = maintainerSupplier(installed.get(c.name)?.maintainer);
    if (supplier) c.supplier = supplier;
  }
  if (isDeb(c) && !(c.licenses || []).length) {
    const lic = licensesOf(c.name);
    if (lic.length) c.licenses = lic;
  }
}

// Components the image ships outside dpkg, listed in security/components.json.
const extras = [];
if (args.components && existsSync(args.components)) {
  const list = JSON.parse(readFileSync(args.components, 'utf8')).components || [];
  for (const e of list.filter((x) => x.image === args.dir)) {
    const [cmd, ...rest] = e.versionCommand;
    const raw = execFileSync('docker', ['run', '--rm', '--network', 'none', '--entrypoint', cmd, args.ref, ...rest], { encoding: 'utf8' }).trim();
    const version = raw.replace(new RegExp(`^${e.versionPrefix || ''}`), '');
    if (!/^[0-9][0-9A-Za-z.+-]*$/.test(version)) { console.error(`image-sbom: unexpected version "${raw}" for ${e.name}`); process.exit(1); }
    const fill = (s) => (s ? s.replaceAll('{version}', version) : undefined);
    const purl = fill(e.purl);
    extras.push({
      'bom-ref': purl, type: e.type || 'application', name: e.name, version, purl,
      ...(e.group ? { group: e.group } : {}),
      ...(e.cpe ? { cpe: fill(e.cpe) } : {}),
      ...(e.supplier ? { supplier: { name: e.supplier } } : {}),
      ...(e.license ? { licenses: [{ license: { id: e.license } }] } : {}),
      ...(e.description ? { description: e.description } : {}),
    });
  }
}

const root = {
  'bom-ref': `pkg:oci/${args.name}@${args.version}`,
  type: 'container', name: args.name, version: args.version,
  purl: `pkg:oci/${args.name}@${args.version}?repository_url=ghcr.io/autonomy-logic/${args.name}&tag=${args.version}`,
};
bom.metadata = { ...bom.metadata, component: root };
bom.components = [...components, ...extras];
const refs = new Set(bom.components.map(refOf));
bom.dependencies = (bom.dependencies || [])
  .filter((d) => d.ref === oldRoot || refs.has(d.ref))
  .map((d) => ({
    ref: d.ref === oldRoot ? root['bom-ref'] : d.ref,
    dependsOn: [...(d.dependsOn || []).filter((r) => refs.has(r)), ...(d.ref === oldRoot ? [...added, ...extras.map(refOf)] : [])],
  }));
if (!bom.dependencies.some((d) => d.ref === root['bom-ref'])) {
  bom.dependencies.push({ ref: root['bom-ref'], dependsOn: bom.components.map(refOf) });
}
writeFileSync(args.out, JSON.stringify(bom, null, 2) + '\n');
const unlicensed = bom.components.filter((c) => !(c.licenses || []).length).length;
console.log(`Wrote ${args.out}: ${bom.components.length} components (${extras.length} outside dpkg, ${unlicensed} without a licence).`);
