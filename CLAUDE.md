# CLAUDE.md

## What this repository is

`autonomy-docker` builds the base images of the Autonomy Node product images and publishes them to
`ghcr.io/autonomy-logic`. The policy for images, versions, tags and the bump cascade is in [README.md](README.md).

## Layout

- `images.conf`: the image list, one `<dir> <package> <parent-dir or ->` row per image.
- `<dir>/Dockerfile`, `<dir>/VERSION`: one directory per image (`root`, `python`, `node`).
- `docker-bake.hcl`: the build graph; a child builds on the context `parent`.
- `scripts/check-versions.sh`: pull request gate for the `VERSION` rules.
- `scripts/existing-tag.sh`, `scripts/verify-parent.sh`: attestation checks of an existing tag and of a parent.
- `scripts/publish-plan.sh`, `scripts/publish-image.sh`: the publish jobs; `scripts/setup-builder.sh`: the builder.
- `scripts/lib/`: `tag-digest.sh` and `tag-exists.sh` (registry), `verify-attestation.sh` (`gh`), `images.sh`
  (image list loader).
- `tests/check-versions/`, `tests/publish-checks/`: plain bash tests of the scripts; `run.sh` is the entry point.
- `tests/<dir>/run.sh <image> <platform>`: smoke test of an image; `tests/smoke.sh` and `tests/reproducible.sh`
  build every image.
- `.github/workflows/build.yml`: pull request checks, with the job `ci` as the single gate check, and the publish
  jobs `plan` and `publish`.
- `.github/CODEOWNERS`, `.github/dependabot.yml`, `SECURITY.md`, `LICENSE`.

## Commands

```sh
tests/check-versions/run.sh
tests/publish-checks/run.sh
shellcheck scripts/*.sh scripts/lib/*.sh tests/*.sh tests/*/*.sh
scripts/check-versions.sh --base origin/main --head HEAD
SOURCE_DATE_EPOCH="$(git log -1 --pretty=%ct)" docker buildx bake
```

## Conventions

- Scripts need bash 4 or later (`#!/usr/bin/env bash`, `set -u`, `set -o pipefail`, no `eval`, quoted expansions)
  and stay `shellcheck` clean. Tests use no network and no global git config.
- LF line endings (`.gitattributes`); `.sh` files are committed with mode 100755.
- Workflow actions are pinned by a bare full 40-character commit SHA, with no trailing comment. Images used by the
  build (`scripts/setup-builder.sh`, the SBOM generator in `scripts/publish-image.sh`) are pinned by digest.
- Only the job `publish` has write permissions, and it restores no cache.
- Values reach a workflow `run:` step only through `env:`, never as a `${{ }}` expression in the script text.
- Comments are minimal: a short description above a function, nothing else.
- The job id `ci` is fixed because it is the required status check of `main`; the workflow file name
  `.github/workflows/build.yml` is fixed because product repositories verify the images against it as the signer workflow.

## License

GPL-3.0, see [LICENSE](LICENSE).
