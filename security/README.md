# Security — SBOM and vulnerability flows

This repository ships Docker base images, not a package-manager project. The SBOM and the vulnerability scans
therefore describe the images: every image listed in `images.conf`, built from the commit with `docker buildx bake`
for `linux/amd64` by `scripts/build-images.sh`.

Two separate flows, run by GitHub Actions:

| Flow | What it is | When it runs | Output |
|---|---|---|---|
| **SBOM** (`security-sbom.yml`) | One bill of materials per image: every installed package with its version and licence (CycloneDX 1.6, SPDX 2.3, components CSV) | Once per release: a commit landing on `main` | Branch `security-archive`, folder `pr-<n>-<date>/` |
| **Vulnerabilities, PR check** (`security-pr-gate.yml`) | osv-scanner on the images of the PR head and base | Every PR into `main` (or `development`) | Blocks only a **critical advisory the PR introduces**; pre-existing advisories never block. Sticky PR comment, no SBOM, no report |
| **Vulnerabilities, release report** (`security-release-vulns.yml`) | Image scan plus the vulnerability report (md, html, pdf) | Once per release, next to the SBOM | Same `security-archive` folder as the SBOM |
| **Vulnerabilities, monthly** (`security-monthly.yml`) | Image scan of `main`, Claude triage of new advisories, vulnerability report | 1st of every month, 06:00 UTC, and on demand | A PR into `main` with `security/<YYYY-MM>/` |

The vulnerability flows scan the image archives directly (`scripts/scan-images.sh`, which always takes an explicit
osv-scanner config) and honour the VEX baseline in `../osv-scanner.toml`; they do not need the SBOM. The release and
monthly reports also run an unfiltered scan with the empty `osv-raw.toml`, so the raw and suppressed figures differ
whenever the baseline suppresses something. A commit on `main` that only touches `security/` and
`osv-scanner.toml` (such as the merged monthly PR) is not a release, so the release flows skip it.

```
security-archive (orphan branch)
└── pr-<n>-<date>/
    ├── <package>.cdx.json · <package>.spdx.json · <package>.components.csv  (one set per image)
    ├── PROVENANCE-sbom.txt                                                   ← SBOM flow
    └── vulnerabilities.csv · <Title>-Vulnerability-Report.md/.html/.pdf · PROVENANCE-vulns.txt ← vulnerability flow

security/ (this folder, on main)
├── <YYYY-MM>/             ← monthly vulnerability snapshot
├── LATEST                 ← text file naming the current month
├── components.json        ← components an image ships outside dpkg
├── osv-raw.toml           ← empty osv-scanner config for the unfiltered scan
└── report-config.json     ← report DATA (VEX triage + narrative)
```

> To test the release flows without touching the real evidence, run them with **Run workflow** on any branch other
> than `main`; they write to `archive_branch` (default `security-archive-test`). On `main` the input is ignored and the
> flows always write `security-archive`; `scripts/security-archive.sh` refuses `security-archive` from any other ref.
> `on: schedule` only fires from the default branch.

## Coverage

What the SBOM of each image contains:

- **Debian packages**: every package in the dpkg database of the built image. cdxgen (`-t docker`, pinned in
  `scripts/generate-sbom.sh`) reads the image archive; `scripts/image-sbom.mjs` keeps the packages dpkg reports as
  installed, drops cdxgen's source-package and shared-library file entries, and adds any installed package cdxgen
  missed (marked with the property `autonomy:inventory=dpkg-status`). The package count always equals
  `dpkg-query -W` in the image.
- **Licences**: read from `/usr/share/doc/<package>/copyright` in the image (the root image keeps these files). When
  every `License:` name of a machine-readable (DEP-5) file maps to SPDX, the component carries one SPDX expression
  (`AND` across the file's stanzas); otherwise it lists the Debian names as written, and the SPDX document says
  `NOASSERTION`. Packages whose copyright file is not machine-readable have no licence in the SBOM.
- **Components outside dpkg**: listed by hand in `components.json`; the version is read from the built image at SBOM
  time. Today this is the Node.js binary of `autonomy-node-base`, copied from the pinned `node:22-bookworm-slim`.
- **Supplier**: the image itself names Autonomy Logic, a Debian package the `Maintainer` of its dpkg entry, and a
  `components.json` entry its upstream (`supplier`). A component with none of them is `NOASSERTION` in the SPDX
  document.

What the vulnerability scans cover: the Debian packages of every image, matched by osv-scanner against OSV (Debian
advisories are reported against the source package). Package names in the register and the report carry the image
as a prefix, e.g. `autonomy-node-base/curl`, so an advisory that a PR brings into another image counts as
introduced.

Not covered:

- the Node.js binary in `autonomy-node-base` is in the SBOM but not in the scans: OSV has no Node.js runtime
  advisories. Its version follows the pinned upstream digest in `node/Dockerfile`;
- the `linux/arm64` and `linux/arm/v7` builds: they install the same Debian versions from the same snapshot, so the
  `linux/amd64` inventory stands for them;
- the upstream images themselves beyond what the built image keeps, and the build tooling (`scripts/`, the builder
  images pinned in `scripts/setup-builder.sh`), which does not ship.

## What stops a bad report from shipping

- **`scripts/assert-sbom.mjs`**: a content floor on each image SBOM (20 components); `scripts/image-sbom.mjs` also
  stops when the image has no dpkg inventory. The release SBOM flow asserts the CycloneDX, SPDX and CSV component
  counts of each image agree before archiving.
- **Fail-closed scans**: `scripts/scan-images.sh` stops on any osv-scanner exit code other than 0 or 1, and
  `merge-image-scans.mjs`, `scan-vulns.mjs` and `pr-gate-diff.mjs` refuse a missing or shapeless scan.
- **Untriaged detection**: each entry in `affected[]` / `mitigated[]` / `notAffected[]` of `report-config.json` must
  list the advisory `ids` it accounts for (a test and the monthly validation step enforce it). `build-report.mjs`
  lists anything unclaimed in section 4a and marks the executive summary *Assessment incomplete*; an id claims every
  alias of its advisory.
- **`scripts/lib/severity.mjs` and `scripts/lib/cdx.mjs`**: one severity verdict and one component walk, shared by the
  gate, the report and the SPDX and CSV converters. The OSV records of one issue on one package (a `DEBIAN-CVE-*`
  record and its CVE or GHSA aliases) count as one advisory, with the highest severity any member or osv-scanner group
  carries. An advisory with no parsable severity is `UNKNOWN`: listed, never guessed into a bucket, never blocking.
  `vulnerabilities.csv` is written from the same index, so its row count equals the report's register count.

## The suppression baseline (`../osv-scanner.toml`)

An entry suppresses an advisory id in every image. Suppressions written by the automated triage step carry
`AI-TRIAGED [unreviewed]` in their `reason`; clearing that marker is the reviewer's acknowledgement that a person
checked it. A step after the triage re-parses both files, refuses a net loss of suppressions, refuses more than 15
new suppressions in one run and refuses a triage entry without `ids`. The triage prompt treats advisory text as
untrusted data.

To re-baseline by hand from a triaged register:

```sh
node scripts/gen-osv-ignores.mjs vulnerabilities.csv 2027-01-01 >> osv-scanner.toml
```

## Running locally

The scripts need bash 4, Node.js 22, Docker with Buildx and, for the scans, osv-scanner v2.4.0 on the `PATH`.

```sh
scripts/generate-sbom.sh                      # builds every image, writes sbom/<package>.{cdx.json,spdx.json,components.csv}
mkdir -p /tmp/images
scripts/build-images.sh . sbom.local /tmp/images > /tmp/images/images.txt
scripts/scan-images.sh /tmp/images /tmp/osv.json osv-scanner.toml
scripts/scan-images.sh /tmp/images /tmp/osv-raw.json security/osv-raw.toml
node --test scripts/__tests__/security-scripts.test.mjs
```

cdxgen finds Debian packages through its trivy plugin. It works on a glibc `linux/amd64` host such as the GitHub
runner; on Alpine (musl) the plugin finds no OS packages and `generate-sbom.sh` stops at the content floor.

## One-time setup — run Claude on your subscription (no API key)

1. On your machine: `claude setup-token`, complete the browser login and copy the token it prints.
2. In the repository: **Settings → Secrets and variables → Actions → New repository secret**, name
   `CLAUDE_CODE_OAUTH_TOKEN`, value the token.
3. Without the secret the monthly workflow still runs and builds the report; it only skips the triage step.

A pull request opened with the default `GITHUB_TOKEN` does not trigger other workflows. Set a `SECURITY_BOT_TOKEN`
secret (GitHub App installation token or fine-grained PAT with contents and pull request write) for the checks to
run on the monthly PR.

## Reviewing the monthly PR

- **No new advisory:** confirm the summary, approve, merge.
- **New advisory, not exploitable:** check the justification in the `osv-scanner.toml` diff, drop the
  `AI-TRIAGED [unreviewed]` marker from the entries you verified, then merge.
- **New advisory, exploitable:** raise `DEBIAN_SNAPSHOT` (or the upstream digest) with the `VERSION` bump cascade in a
  separate PR, and merge the report that documents it.
- **Report says *Assessment incomplete*:** section 4a lists advisories nothing accounted for; each needs a fix or a
  documented `not_affected` determination with its id recorded in `report-config.json`.
