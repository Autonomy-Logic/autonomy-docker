# autonomy-docker

The central repository that builds the base images of the Autonomy Node product images and publishes them to
`ghcr.io/autonomy-logic`.

## Images

`images.conf` is the source of the image list. No image is published yet.

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
| `scripts/` | Repository scripts, including the pull request version gate. |
| `tests/` | Tests of the repository scripts. |
| `.github/workflows/build.yml` | Pull request checks. |
| `.github/workflows/drift.yml` | Drift check. |

The image directories, `docker-bake.hcl` and `drift.yml` are planned and not in the repository yet.

## Base-image policy

This section holds the rules for choosing, pinning and updating the upstream base images.

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

This section holds the step-by-step procedure for bumping an image and its descendants.

## Building locally

The images build with Docker Buildx from `docker-bake.hcl`; this section holds the build commands.

## Drift check

This section holds how the drift check detects upstream base-image changes and what to do when it fails.

## Pull request checks

Every pull request to `main` runs `.github/workflows/build.yml`. Its job `ci` is the single gate check: it passes only
when every job it depends on succeeds. Today it depends on `check-versions`, which runs `shellcheck` on the scripts and
tests, the tests of the version gate, and `scripts/check-versions.sh` against the base of the pull request.

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
called as `"$TAG_EXISTS" <registry> <package> <tag>`. `scripts/lib/tag-exists.sh` queries `ghcr.io` anonymously and
exits 0 when the tag exists, 1 when it or the package is absent, 2 on any error.

### Running the checks locally

The scripts need bash 4 or later (on macOS, install a current bash, for example with Homebrew).

```sh
tests/check-versions/run.sh
shellcheck scripts/*.sh scripts/lib/*.sh tests/check-versions/*.sh
scripts/check-versions.sh --base origin/main --head HEAD
```

## Contributing

Only maintainers can create or update branches and tags in this repository. Everyone else opens a pull request from
a fork. Every change needs the review of a code owner (`.github/CODEOWNERS`).

## Security

Report a vulnerability as described in [SECURITY.md](SECURITY.md).

A package version can be deleted only by a repository admin; no workflow deletes a version. A deleted version can be
restored within 30 days.

## License

This repository is licensed under the GNU General Public License version 3. See [LICENSE](LICENSE).
