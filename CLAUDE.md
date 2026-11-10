# CLAUDE.md

## What this repository is

`autonomy-docker` builds the base images of the Autonomy Node product images and publishes them to
`ghcr.io/autonomy-logic`. The policy for images, versions, tags and the bump cascade is in [README.md](README.md).

## Layout

- `images.conf`: the image list, one `<dir> <package> <parent-dir or ->` row per image (empty today).
- `<dir>/Dockerfile`, `<dir>/VERSION`: one directory per image (none yet).
- `scripts/check-versions.sh`: pull request gate for the `VERSION` rules.
- `scripts/lib/tag-exists.sh`: anonymous `ghcr.io` check of whether a tag is published.
- `tests/check-versions/`: plain bash tests of the gate; `run.sh` is the entry point.
- `.github/workflows/build.yml`: pull request checks; the job `ci` is the single gate check.
- `.github/CODEOWNERS`, `.github/dependabot.yml`, `SECURITY.md`, `LICENSE`.

## Commands

```sh
tests/check-versions/run.sh
shellcheck scripts/*.sh scripts/lib/*.sh tests/check-versions/*.sh
scripts/check-versions.sh --base origin/main --head HEAD
```

## Conventions

- Scripts need bash 4 or later (`#!/usr/bin/env bash`, `set -u`, `set -o pipefail`, no `eval`, quoted expansions)
  and stay `shellcheck` clean. Tests use no network and no global git config.
- LF line endings (`.gitattributes`); `.sh` files are committed with mode 100755.
- Workflow actions are pinned by a bare full 40-character commit SHA, with no trailing comment.
- Values reach a workflow `run:` step only through `env:`, never as a `${{ }}` expression in the script text.
- Comments are minimal: a short description above a function, nothing else.
- The job id `ci` is fixed because it is the required status check of `main`; the workflow file name
  `.github/workflows/build.yml` is fixed because product repositories verify the images against it as the signer workflow.

## License

GPL-3.0, see [LICENSE](LICENSE).
