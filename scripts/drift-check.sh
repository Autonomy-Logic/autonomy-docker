#!/usr/bin/env bash
set -u
set -o pipefail

if [ -z "${BASH_VERSINFO[0]:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  printf 'drift-check: bash 4 or later is required\n' >&2
  exit 2
fi

if [ "$#" -ne 2 ]; then
  printf 'usage: drift-check.sh <registry> <out-dir>\n' >&2
  exit 2
fi

export LC_ALL=C

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/images.sh
. "$SCRIPTS_DIR/lib/images.sh"

readonly PLATFORMS=(linux/amd64 linux/arm64 linux/arm/v7)
readonly SEVERITIES=(CRITICAL HIGH MEDIUM LOW)
readonly MAX_FINDINGS=30
readonly DIGEST_RE='^sha256:[0-9a-f]{64}$'
readonly FROM_RE='^FROM[[:space:]]+([a-z0-9][a-z0-9._/-]*:[A-Za-z0-9_][A-Za-z0-9_.-]*)@(sha256:[0-9a-f]{64})([[:space:]]|$)'
readonly INST_RE='^Inst ([^ ]+) \[([^]]+)\] \(([^ ]+) (.*)\)$'
# shellcheck disable=SC2016
readonly PENDING_SCRIPT='
  . /etc/os-release
  rm -f /etc/apt/sources.list.d/*
  cat >/etc/apt/sources.list.d/live.sources <<EOF
Types: deb
URIs: http://deb.debian.org/debian
Suites: ${VERSION_CODENAME} ${VERSION_CODENAME}-updates
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.pgp

Types: deb
URIs: http://security.debian.org/debian-security
Suites: ${VERSION_CODENAME}-security
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.pgp
EOF
  apt-get update -qq
  apt-get -s upgrade >/tmp/drift-upgrade
  grep "^Inst " /tmp/drift-upgrade || true
'

registry="$1"
out="$2"
export REGISTRY="$registry"

PIN_DIR=()
PIN_REF=()
PIN_OLD=()
PIN_NEW=()
REASONS=()
declare -A AFFECTED=() PUBLISHED=()
S_UPSTREAM=""
S_BUILD=""
S_UPDATES=""
S_SCAN=""
S_FINDINGS=""

# Prints an error and ends the run with the tool error code.
die() {
  printf 'drift-check: %s\n' "$*" >&2
  exit 2
}

# Prints a value from an upstream source with every character outside a safe set replaced.
clean() {
  printf '%s' "${1//[^A-Za-z0-9._+~:\/-]/?}"
}

# Compares every digest-pinned FROM of the image directories with what its tag resolves to now.
check_upstream() {
  local dir line ref pinned current moved
  S_UPSTREAM=$'| Image | Input | Pinned digest | Current digest | Moved |\n| --- | --- | --- | --- | --- |\n'
  for dir in "${IMG_DIRS[@]}"; do
    while IFS= read -r line || [ -n "$line" ]; do
      [[ $line =~ $FROM_RE ]] || continue
      ref="${BASH_REMATCH[1]}"
      pinned="${BASH_REMATCH[2]}"
      current="$(docker buildx imagetools inspect "$ref" --format '{{.Manifest.Digest}}')" ||
        die "cannot resolve $ref"
      [[ $current =~ $DIGEST_RE ]] || die "no valid digest for $ref"
      moved=no
      if [ "$current" != "$pinned" ]; then
        moved=yes
        REASONS+=("The upstream input \`$ref\` of \`$dir\` moved.")
      fi
      PIN_DIR+=("$dir")
      PIN_REF+=("$ref")
      PIN_OLD+=("$pinned")
      PIN_NEW+=("$current")
      S_UPSTREAM+="| \`$dir\` | \`$ref\` | \`$pinned\` | \`$current\` | $moved |"$'\n'
    done <"$dir/Dockerfile"
  done
}

# Builds the images whose input moved, and their descendants, on the new digests and runs their smoke tests.
build_moved() {
  local i dir platform result override="$out/drift-bake.json" targets=()
  printf '{}\n' >"$override"
  for i in "${!PIN_DIR[@]}"; do
    [ "${PIN_OLD[$i]}" != "${PIN_NEW[$i]}" ] || continue
    AFFECTED[${PIN_DIR[$i]}]=1
    jq --arg dir "${PIN_DIR[$i]}" --arg key "${PIN_REF[$i]}@${PIN_OLD[$i]}" \
      --arg value "docker-image://${PIN_REF[$i]}@${PIN_NEW[$i]}" \
      '.target[$dir].contexts[$key] = $value' "$override" >"$override.next" || die "cannot write $override"
    mv "$override.next" "$override"
  done
  for dir in "${IMG_DIRS[@]}"; do
    if [ -n "${AFFECTED[$dir]+set}" ] || [ -n "${AFFECTED[${IMG_PARENT[$dir]}]+set}" ]; then
      AFFECTED[$dir]=1
      targets+=("$dir")
    fi
  done
  if [ "${#targets[@]}" -eq 0 ]; then
    S_BUILD=$'No upstream input moved, so nothing was built.\n'
    return 0
  fi
  S_BUILD=$'| Image | Platform | Result |\n| --- | --- | --- |\n'
  for platform in "${PLATFORMS[@]}"; do
    if docker buildx bake -f docker-bake.hcl -f "$override" "${targets[@]}" --provenance=false --sbom=false \
      --set "*.platforms=$platform" --set "*.output=type=docker"; then
      for dir in "${targets[@]}"; do
        result=passed
        if ! "tests/$dir/run.sh" "$registry/${IMG_PKG[$dir]}:dev" "$platform"; then
          result="smoke test failed"
          REASONS+=("The smoke test of \`$dir\` failed on the moved input ($platform).")
        fi
        S_BUILD+="| \`$dir\` | $platform | $result |"$'\n'
      done
    else
      REASONS+=("The build on the moved input failed ($platform).")
      for dir in "${targets[@]}"; do
        S_BUILD+="| \`$dir\` | $platform | build failed |"$'\n'
      done
    fi
  done
}

# Resolves the digest of every published base tag into PUBLISHED.
resolve_published() {
  local dir digest rc
  for dir in "${IMG_DIRS[@]}"; do
    rc=0
    digest="$("$SCRIPTS_DIR/lib/tag-digest.sh" "$registry" "${IMG_PKG[$dir]}" "${IMG_TAG[$dir]}")" || rc=$?
    case "$rc" in
      0) PUBLISHED[$dir]="$digest" ;;
      1) ;;
      *) die "cannot resolve ${IMG_PKG[$dir]}:${IMG_TAG[$dir]}" ;;
    esac
  done
}

# Lists the Debian updates each published base does not carry, security updates apart.
check_updates() {
  local dir ref pending line security other list
  S_UPDATES=$'| Base | Published digest | Security updates | Other updates |\n| --- | --- | --- | --- |\n'
  list=""
  for dir in "${IMG_DIRS[@]}"; do
    ref="$registry/${IMG_PKG[$dir]}:${IMG_TAG[$dir]}"
    if [ -z "${PUBLISHED[$dir]+set}" ]; then
      S_UPDATES+="| \`$ref\` | not published | - | - |"$'\n'
      continue
    fi
    pending="$(docker run --rm --user 0 --platform linux/amd64 "$ref@${PUBLISHED[$dir]}" sh -euc "$PENDING_SCRIPT")" ||
      die "cannot list the pending updates of $ref"
    security=0
    other=0
    while IFS= read -r line; do
      [[ $line =~ $INST_RE ]] || continue
      if [[ ${BASH_REMATCH[4]} == *Debian-Security* ]]; then
        security=$((security + 1))
        list+="| \`$ref\` | $(clean "${BASH_REMATCH[1]}") | $(clean "${BASH_REMATCH[2]}") | $(clean "${BASH_REMATCH[3]}") |"$'\n'
      else
        other=$((other + 1))
      fi
    done <<<"$pending"
    if [ "$security" -gt 0 ]; then
      REASONS+=("\`$ref\` has $security pending Debian security updates.")
    fi
    S_UPDATES+="| \`$ref\` | \`${PUBLISHED[$dir]}\` | $security | $other |"$'\n'
  done
  if [ -n "$list" ]; then
    S_UPDATES+=$'\n| Base | Package | Installed | Security update |\n| --- | --- | --- | --- |\n'"$list"
  fi
}

# Scans every published base on every platform and counts the findings by severity.
scan_published() {
  local dir ref platform file severity counts total fixable urgent shown line id pkg installed fixed
  mkdir -p "$out/scan" || die "cannot create $out/scan"
  S_SCAN=$'Each cell is the number of findings, then how many of them have a fixed version.\n\n'
  S_SCAN+=$'| Base | Platform | Critical | High | Medium | Low |\n| --- | --- | --- | --- | --- | --- |\n'
  for dir in "${IMG_DIRS[@]}"; do
    [ -n "${PUBLISHED[$dir]+set}" ] || continue
    ref="$registry/${IMG_PKG[$dir]}:${IMG_TAG[$dir]}"
    urgent=""
    for platform in "${PLATFORMS[@]}"; do
      file="$out/scan/${IMG_PKG[$dir]}-${platform//\//-}.json"
      trivy image --quiet --scanners vuln --format json --platform "$platform" --output "$file" \
        "$ref@${PUBLISHED[$dir]}" || die "the scan of $ref ($platform) failed"
      counts=""
      for severity in "${SEVERITIES[@]}"; do
        total="$(jq --arg s "$severity" '[.Results[]?.Vulnerabilities[]? | select(.Severity == $s)] | length' "$file")" ||
          die "cannot read $file"
        fixable="$(jq --arg s "$severity" \
          '[.Results[]?.Vulnerabilities[]? | select(.Severity == $s and (.FixedVersion // "") != "")] | length' "$file")" ||
          die "cannot read $file"
        counts+=" $total ($fixable) |"
      done
      S_SCAN+="| \`$ref\` | $platform |$counts"$'\n'
      urgent+="$(jq -r '.Results[]?.Vulnerabilities[]?
        | select((.Severity == "CRITICAL" or .Severity == "HIGH") and (.FixedVersion // "") != "")
        | [.Severity, .VulnerabilityID, .PkgName, .InstalledVersion, .FixedVersion] | @tsv' "$file")"$'\n' ||
        die "cannot read $file"
    done
    urgent="$(printf '%s' "$urgent" | sort -u | sed '/^$/d')"
    [ -n "$urgent" ] || continue
    total="$(printf '%s\n' "$urgent" | wc -l | tr -d ' ')"
    REASONS+=("\`$ref\` has $total Critical or High findings with a fixed version.")
    shown=0
    while IFS=$'\t' read -r severity id pkg installed fixed; do
      shown=$((shown + 1))
      [ "$shown" -le "$MAX_FINDINGS" ] || break
      line="| \`$ref\` | $(clean "$severity") | $(clean "$id") | $(clean "$pkg") | $(clean "$installed") | $(clean "$fixed") |"
      S_FINDINGS+="$line"$'\n'
    done <<<"$urgent"
    if [ "$total" -gt "$MAX_FINDINGS" ]; then
      S_FINDINGS+="| \`$ref\` | | and $((total - MAX_FINDINGS)) more, in the scan files of the run | | | |"$'\n'
    fi
  done
}

# Writes the report and the action flag.
write_report() {
  local reason
  {
    printf '# Drift report of %s\n\n' "$(date -u +%Y-%m-%d)"
    printf "Commit \`%s\`. Scanner: %s.\n\n" "${GITHUB_SHA:-unknown}" "$(clean "$(trivy --version | head -n 1)")"
    printf '## Action needed\n\n'
    if [ "${#REASONS[@]}" -eq 0 ]; then
      printf 'None.\n'
    else
      for reason in "${REASONS[@]}"; do
        printf -- '- %s\n' "$reason"
      done
    fi
    printf '\n## Upstream inputs\n\n%s' "$S_UPSTREAM"
    printf '\n## Build and test on the moved inputs\n\n%s' "$S_BUILD"
    printf '\n## Pending Debian updates\n\n%s' "$S_UPDATES"
    printf '\n## Image scan\n\n%s' "$S_SCAN"
    if [ -n "$S_FINDINGS" ]; then
      printf '\n### Critical and High findings with a fixed version\n\n'
      printf '| Base | Severity | ID | Package | Installed | Fixed |\n| --- | --- | --- | --- | --- | --- |\n%s' "$S_FINDINGS"
    fi
  } >"$out/report.md" || die "cannot write $out/report.md"
  if [ "${#REASONS[@]}" -eq 0 ]; then
    printf 'no\n' >"$out/action-needed"
  else
    printf 'yes\n' >"$out/action-needed"
  fi
}

load_images || exit 2
mkdir -p "$out" || die "cannot create $out"
check_upstream
build_moved
resolve_published
check_updates
scan_published
write_report
