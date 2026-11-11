# autonomy-docker

The central repository that builds the base images of the Autonomy Node product images and publishes them to
`ghcr.io/autonomy-logic`.

## Images

`images.conf` is the source of the image list.

| Directory | Package | Tag | Contents | Built on |
| --- | --- | --- | --- | --- |
| `root` | `ghcr.io/autonomy-logic/autonomy-base` | `trixie-1` | Debian 13 slim, dpkg path excludes (docs, man pages, locales, sanitizer runtimes), apt on the Debian snapshot `20261110T000000Z`, `ca-certificates` | `debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2` |
| `python` | `ghcr.io/autonomy-logic/autonomy-python-base` | `py3.13-trixie-1` | `root` plus Debian `python3` 3.13 and `libpython3.13` | `root` |

Every image is built for `linux/amd64`, `linux/arm64` and `linux/arm/v7`. A product pins a base by tag and digest,
`FROM <package>:<tag>@sha256:<digest>`; the publish run prints that line in its summary.

## Layout

| Path | Purpose |
| --- | --- |
| `root/Dockerfile`, `root/VERSION` | Root base image. |
| `python/Dockerfile`, `python/VERSION` | Python base image. |
| `node/Dockerfile`, `node/VERSION` | Node.js base image. |
| `runtime/Dockerfile`, `runtime/VERSION` | Base image of the PLC runtime image. |
| `orchestrator/Dockerfile`, `orchestrator/VERSION` | Base image of the orchestrator agent image. |
| `netmon/Dockerfile`, `netmon/VERSION` | Base image of the network monitor image. |
| `docker-bake.hcl` | Docker Buildx bake definition of every image. |
| `images.conf` | Image list: directory, package and parent of each image. |
| `scripts/` | Repository scripts: the pull request version gate and the publish checks. |
| `tests/` | Tests of the repository scripts and one smoke test per image, `tests/<dir>/run.sh`. |
| `.github/workflows/build.yml` | Pull request checks and the publish jobs. |
| `.github/workflows/drift.yml` | Drift check. |

The `node`, `runtime`, `orchestrator` and `netmon` directories and `drift.yml` are planned and not in the repository
yet.

## Base-image policy

- The root image starts from an upstream image pinned by digest. No Dockerfile uses a floating upstream tag.
- apt reads the Debian snapshot named by `DEBIAN_SNAPSHOT` in `root/Dockerfile`. The snapshot stays in the apt sources
  of the image, so every image built on the root installs from the same package set.
- An upstream digest or the snapshot changes only through a reviewed pull request that bumps `root/VERSION` and the
  `VERSION` of every descendant. Until that bump, no Debian update reaches the images.
- A child image names its parent as the build context `parent` (`FROM parent`); `docker-bake.hcl` resolves it. The
  labels `org.opencontainers.image.base.name` and `org.opencontainers.image.base.digest` of a published child hold the
  tag and the digest of the parent it was built on.

## Versions and tags

### `VERSION`

Each image directory has a `VERSION` file holding the image tag: one line, ending with a newline, nothing else. The
tag matches `^[a-z][a-z0-9.]*(-[a-z][a-z0-9.]*)*-[1-9][0-9]*$`, for example `trixie-1`, `py3.13-trixie-1` or
`node22-trixie-1`. The family is everything before the last `-`; `N` is the last field.

A change of `VERSION`, compared with the merge-base of the pull request, is one of:

- the same family with `N` + 1 (`trixie-3` to `trixie-4`);
- a new family with `N` = 1 (`trixie-4` to `forky-1`);
- a new image with `N` = 1.

Any other change, such as `N` + 2, a decrease or a new family starting above 1, is rejected.

### `images.conf`

One image per line, three fields separated by spaces or tabs:

```
<dir> <package> <parent-dir or ->
```

- `<dir>` is the image directory and `<package>` the package name on `ghcr.io/autonomy-logic`; both match
  `^[a-z][a-z0-9-]*$`.
- `<parent-dir>` is the `<dir>` of the image it builds on, or `-` for an image with no parent in this repository.
- Every `<dir>` exists and has a `VERSION`; every `<dir>` and every package appear once.
- A parent is a `<dir>` on an earlier line, so the list has no cycle.
- Empty lines are ignored. There are no comment lines.

### Tags

A tag is published only when it is absent from the registry. A published tag is never moved or overwritten, and
there is no floating tag such as `latest`: every reference names a `VERSION` tag.

## Bump cascade

This section holds how a change to a parent image propagates to the images built on it.

Enforced rule: when the `VERSION` of an image changes, the `VERSION` of every descendant in `images.conf` (children,
grandchildren and further) changes in the same pull request.

## Bump procedure

1. Change the image directory and raise its `VERSION` by one. In the root, update the upstream digest and
   `DEBIAN_SNAPSHOT` together.
2. Raise the `VERSION` of every descendant in `images.conf`.
3. Update the image table of this README.
4. Open the pull request; `scripts/check-versions.sh --base origin/main --head HEAD` lists the tags it will publish.
5. After the merge, the publish run prints the pinned `FROM` line of each new tag for the product pull requests.

Adding an image also needs its row in `images.conf`, its target and variables in `docker-bake.hcl`
(`<DIR>_PACKAGE`, `<DIR>_TAG`, and `<DIR>_DIGEST` when it has children) and its smoke test `tests/<dir>/run.sh`.

## Building locally

The images build with Docker Buildx from `docker-bake.hcl`. `SOURCE_DATE_EPOCH` is the commit time; file times later
than it are rewritten to it, so two builds of one commit give the same layers. With the default `0` the Python
bytecode shipped by Debian no longer matches its sources, and the Python smoke test fails.

```sh
export SOURCE_DATE_EPOCH="$(git log -1 --pretty=%ct)"
docker buildx bake
tests/python/run.sh ghcr.io/autonomy-logic/autonomy-python-base:dev linux/arm64
```

A local build tags every image `dev` and builds each child on the local build of its parent. Loading the three
platforms at once needs the containerd image store; otherwise `scripts/setup-builder.sh` creates the builder used by
the workflow (`export BUILDX_BUILDER=autonomy`) and `tests/smoke.sh` builds and tests one platform at a time.
`tests/reproducible.sh` builds every image twice without cache and compares the results.

## Drift check

This section holds how the drift check detects upstream base-image changes and what to do when it fails.

## Pull request checks

Every pull request to `main` runs `.github/workflows/build.yml`. Its job `ci` is the single gate check: it passes only
when every job it depends on succeeds. It depends on:

- `check-versions`: `shellcheck` on the scripts and tests, the tests of the version gate and of the publish checks,
  and `scripts/check-versions.sh` against the base of the pull request;
- `images`: builds every image for the three platforms without pushing, runs the smoke tests (`tests/smoke.sh`) and
  the reproducibility check (`tests/reproducible.sh`).

No product image builds on these bases yet, so no pull request job builds a product Dockerfile on the candidate
bases. The check belongs to the first product pin: `docker buildx build --build-context
"<package>:<tag>@sha256:<digest>=docker-image://<candidate>"` replaces a digest-pinned `FROM` when the key is the
full reference, digest included.

### `check-versions.sh`

`scripts/check-versions.sh --base <rev> --head <rev> [--repo <dir>]` compares `head` with the merge-base of `base` and
`head`, reading only committed git objects. An image directory is the `<dir>` of an `images.conf` row at the
merge-base or at head; a change under any other path never needs a bump.

Each violation is one line on stderr, `check-versions: <rule-id>: <dir>: <detail>`, and every violation is reported:

| Rule id | Fails when |
| --- | --- |
| `version-not-bumped` | a file under an image directory changed, or the image's `images.conf` row changed, and its `VERSION` did not |
| `version-format` | a changed or new `VERSION` does not match the format |
| `version-increment` | a `VERSION` change is not an allowed transition |
| `descendant-not-bumped` | an image's `VERSION` changed and a descendant's did not |
| `manifest-invalid` | `images.conf` at head is missing or breaks a rule of its format |
| `tag-exists` | the new tag is already published on the registry |
| `image-removed` | an image of the merge-base `images.conf` is absent from the head `images.conf` |

When `images.conf` at head is invalid, only its `manifest-invalid` violations are reported, because the other rules
need a valid image list. The registry is checked once per image whose new `VERSION` has a valid format.

On a pass, stdout lists one `<package>:<tag>` line per image whose `VERSION` changed or is new, in `images.conf` order.

| Exit code | Meaning |
| --- | --- |
| 0 | Pass, including no image changed and an empty `images.conf`. |
| 1 | At least one violation. |
| 2 | Usage or input error: unknown or missing argument, revision not found, not a git repository, bash older than 4. |
| 3 | The registry check failed for at least one image; the gate fails closed and still prints the violations. |

Environment: `REGISTRY` (default `ghcr.io/autonomy-logic`) and `TAG_EXISTS` (default `scripts/lib/tag-exists.sh`),
called as `"$TAG_EXISTS" <registry> <package> <tag>`. `scripts/lib/tag-exists.sh` queries `ghcr.io` and exits 0 when
the tag exists, 1 when the tag is absent or no public package of that name exists, 2 on any error. It is
`scripts/lib/tag-digest.sh` without its output.

### Running the checks locally

The scripts need bash 4 or later (on macOS, install a current bash, for example with Homebrew).

```sh
tests/check-versions/run.sh
tests/publish-checks/run.sh
shellcheck scripts/*.sh scripts/lib/*.sh tests/*.sh tests/*/*.sh
scripts/check-versions.sh --base origin/main --head HEAD
```

## Publishing

A push to `main` or a manual run of `build.yml` on `main` publishes the tags that are absent from the registry, in
`images.conf` order, parents first. On any other ref the publish jobs do not run.

1. Job `plan` runs `scripts/publish-plan.sh`, which checks every image with `scripts/existing-tag.sh` before any
   push. A failed check ends the run and nothing is pushed.
2. Job `publish` runs once per absent tag, one at a time, in the `publish` environment. It holds the only write
   permissions of the workflow, uses `GITHUB_TOKEN` only and restores no cache. `scripts/publish-image.sh` checks the
   tag again, verifies the parent with `scripts/verify-parent.sh`, then builds and pushes with provenance
   (`mode=max`) and an SBOM. The job attests the pushed digest and prints the pinned `FROM` line in the summary.

| Script | Exit 0 | Exit 1 | Exit 2 |
| --- | --- | --- | --- |
| `scripts/existing-tag.sh <registry> <package> <tag> <signer-workflow> <source-ref>` | stdout `absent <ref>`, or `published <ref>@<digest>` when the tag exists and its digest is attested by the signer on the source ref | the tag exists and its digest is not attested; stderr names the tag and the digest, stdout is empty | registry or tool error |
| `scripts/verify-parent.sh <registry> <package> <tag> <signer-workflow> <source-ref>` | stdout `<ref>@<digest>`, the attested parent | the parent tag is absent, or its digest is not attested; stderr names the tag and the digest | registry or tool error |

The signer is `Autonomy-Logic/autonomy-docker/.github/workflows/build.yml` on `refs/heads/main`. The attestation is
verified with `gh attestation verify --signer-workflow --source-ref --deny-self-hosted-runners`. With `REGISTRY_TOKEN`
set, the registry is queried with that credential, which also sees a private package.

A new package is private until a repository admin makes it public. When a push succeeds and its attestation fails,
the tag exists unattested and every later run stops at `plan`; a repository admin deletes that version, then the
run is repeated.

## Contributing

Only maintainers can create or update branches and tags in this repository. Everyone else opens a pull request from
a fork. Every change needs the review of a code owner (`.github/CODEOWNERS`).

## Security

Report a vulnerability as described in [SECURITY.md](SECURITY.md).

A package version can be deleted only by a repository admin; no workflow deletes a version. A deleted version can be
restored within 30 days.

## License

This repository is licensed under the GNU General Public License version 3. See [LICENSE](LICENSE).
