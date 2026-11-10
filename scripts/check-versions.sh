#!/usr/bin/env bash
set -u
set -o pipefail

if [ -z "${BASH_VERSINFO[0]:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  printf 'check-versions: bash 4 or later is required\n' >&2
  exit 2
fi

export LC_ALL=C

readonly VERSION_RE='^[a-z][a-z0-9.]*(-[a-z][a-z0-9.]*)*-[1-9][0-9]*$'
readonly NAME_RE='^[a-z][a-z0-9-]*$'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="${REGISTRY:-ghcr.io/autonomy-logic}"
TAG_EXISTS="${TAG_EXISTS:-$SCRIPT_DIR/lib/tag-exists.sh}"

# Prints the usage line and an error, then exits with the input-error code.
usage_error() {
  printf 'check-versions: %s\n' "$1" >&2
  printf 'usage: check-versions.sh --base <rev> --head <rev> [--repo <dir>]\n' >&2
  exit 2
}

# Prints one violation line and records that the gate failed.
violation() {
  printf 'check-versions: %s: %s: %s\n' "$1" "$2" "$3" >&2
  VIOLATIONS=$((VIOLATIONS + 1))
}

# Prints the decimal successor of a string of digits, without integer overflow.
decimal_successor() {
  local digits="$1" out="" carry=1 d i
  for ((i = ${#digits} - 1; i >= 0; i--)); do
    d=$((${digits:i:1} + carry))
    if [ "$d" -eq 10 ]; then
      out="0$out"
      carry=1
    else
      out="$d$out"
      carry=0
    fi
  done
  if [ "$carry" -eq 1 ]; then
    out="1$out"
  fi
  printf '%s' "$out"
}

# Succeeds when the object <rev>:<path> exists and has the given type.
object_is() {
  [ "$(git -C "$REPO" cat-file -t "$2:$3" 2>/dev/null)" = "$1" ]
}

# Stores the exact content of the blob <rev>:<path> in BLOB, trailing newlines included.
read_blob() {
  BLOB="$(git -C "$REPO" cat-file blob "$1:$2" && printf x)" || return 1
  BLOB="${BLOB%x}"
}

# Stores the tag of a VERSION content in TAG; fails when the content is not exactly one valid line.
parse_version() {
  local content="$1"
  [ "${content: -1}" = $'\n' ] || return 1
  TAG="${content%$'\n'}"
  case "$TAG" in
    *$'\n'*) return 1 ;;
  esac
  [[ $TAG =~ $VERSION_RE ]]
}

# Parses images.conf of a revision into M_DIRS (ordered), M_PKG and M_PARENT.
# With validate set to 1, every manifest rule is checked and each break is reported as manifest-invalid.
load_manifest() {
  local rev="$1" validate="$2"
  local -A seen_pkg=()
  local line lineno=0 dir pkg parent
  local -a fields
  M_DIRS=()
  M_PKG=()
  M_PARENT=()

  if ! object_is blob "$rev" images.conf; then
    if [ "$validate" = 1 ]; then
      violation manifest-invalid images.conf "images.conf is missing"
    fi
    return 0
  fi
  read_blob "$rev" images.conf || return 1

  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    IFS=$' \t' read -r -a fields <<<"$line"
    [ "${#fields[@]}" -eq 0 ] && continue
    if [ "${#fields[@]}" -ne 3 ]; then
      [ "$validate" = 1 ] && violation manifest-invalid images.conf "line $lineno: expected 3 fields, found ${#fields[@]}"
      continue
    fi
    dir="${fields[0]}"
    pkg="${fields[1]}"
    parent="${fields[2]}"
    if [ -n "${M_PKG[$dir]+set}" ]; then
      [ "$validate" = 1 ] && violation manifest-invalid images.conf "line $lineno: duplicate directory '$dir'"
      continue
    fi
    if [ "$validate" = 1 ]; then
      if ! [[ $dir =~ $NAME_RE ]]; then
        violation manifest-invalid images.conf "line $lineno: invalid directory name '$dir'"
        continue
      fi
      if ! [[ $pkg =~ $NAME_RE ]]; then
        violation manifest-invalid images.conf "line $lineno: invalid package name '$pkg'"
      elif [ -n "${seen_pkg[$pkg]+set}" ]; then
        violation manifest-invalid images.conf "line $lineno: duplicate package '$pkg'"
      fi
      seen_pkg[$pkg]=1
      if [ "$parent" != "-" ] && [ -z "${M_PKG[$parent]+set}" ]; then
        violation manifest-invalid images.conf "line $lineno: parent '$parent' of '$dir' is not a directory on an earlier line"
      fi
      if ! object_is tree "$rev" "$dir"; then
        violation manifest-invalid images.conf "line $lineno: directory '$dir' does not exist"
      elif ! object_is blob "$rev" "$dir/VERSION"; then
        violation manifest-invalid images.conf "line $lineno: '$dir/VERSION' does not exist"
      fi
    fi
    M_DIRS+=("$dir")
    M_PKG[$dir]="$pkg"
    M_PARENT[$dir]="$parent"
  done <<<"${BLOB%$'\n'}"
}

BASE=""
HEAD=""
REPO="."
while [ "$#" -gt 0 ]; do
  case "$1" in
    --base | --head | --repo)
      if [ "$#" -lt 2 ] || [ -z "$2" ] || [ "${2:0:1}" = "-" ]; then
        usage_error "$1 requires a value"
      fi
      case "$1" in
        --base) BASE="$2" ;;
        --head) HEAD="$2" ;;
        --repo) REPO="$2" ;;
      esac
      shift 2
      ;;
    *)
      usage_error "unknown argument: $1"
      ;;
  esac
done

[ -n "$BASE" ] || usage_error "--base is required"
[ -n "$HEAD" ] || usage_error "--head is required"
[ -d "$REPO" ] || usage_error "not a directory: $REPO"
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || usage_error "not a git repository: $REPO"

BASE_SHA="$(git -C "$REPO" rev-parse --verify -q --end-of-options "$BASE^{commit}")" ||
  usage_error "revision not found: $BASE"
HEAD_SHA="$(git -C "$REPO" rev-parse --verify -q --end-of-options "$HEAD^{commit}")" ||
  usage_error "revision not found: $HEAD"
MERGE_BASE="$(git -C "$REPO" merge-base "$BASE_SHA" "$HEAD_SHA")" ||
  usage_error "no merge-base between $BASE and $HEAD"

VIOLATIONS=0
REGISTRY_ERRORS=0
BLOB=""
TAG=""
declare -a M_DIRS=() OLD_DIRS=() NEW_DIRS=()
declare -A M_PKG=() M_PARENT=() OLD_PKG=() OLD_PARENT=() NEW_PKG=() NEW_PARENT=()

load_manifest "$MERGE_BASE" 0 || usage_error "cannot read images.conf at the merge-base"
for dir in ${M_DIRS[@]+"${M_DIRS[@]}"}; do
  OLD_DIRS+=("$dir")
  OLD_PKG[$dir]="${M_PKG[$dir]}"
  OLD_PARENT[$dir]="${M_PARENT[$dir]}"
done
load_manifest "$HEAD_SHA" 1 || usage_error "cannot read images.conf at $HEAD"
for dir in ${M_DIRS[@]+"${M_DIRS[@]}"}; do
  NEW_DIRS+=("$dir")
  NEW_PKG[$dir]="${M_PKG[$dir]}"
  NEW_PARENT[$dir]="${M_PARENT[$dir]}"
done

if [ "$VIOLATIONS" -gt 0 ]; then
  exit 1
fi

DIFF_FILE="$(mktemp)" || usage_error "cannot create a temporary file"
trap 'rm -f "$DIFF_FILE"' EXIT
git -C "$REPO" diff --name-only --no-renames -z "$MERGE_BASE" "$HEAD_SHA" -- >"$DIFF_FILE" ||
  usage_error "cannot diff $MERGE_BASE..$HEAD_SHA"

declare -A TOUCHED=()
while IFS= read -r -d '' path; do
  for dir in ${OLD_DIRS[@]+"${OLD_DIRS[@]}"} ${NEW_DIRS[@]+"${NEW_DIRS[@]}"}; do
    if [[ $path == "$dir"/* ]]; then
      TOUCHED[$dir]=1
    fi
  done
done <"$DIFF_FILE"

for dir in ${OLD_DIRS[@]+"${OLD_DIRS[@]}"}; do
  if [ -z "${NEW_PKG[$dir]+set}" ]; then
    violation image-removed "$dir" "image removed from images.conf"
  fi
done

declare -A BUMPED=()
declare -a PUBLISH=()
for dir in ${NEW_DIRS[@]+"${NEW_DIRS[@]}"}; do
  pkg="${NEW_PKG[$dir]}"
  read_blob "$HEAD_SHA" "$dir/VERSION" || usage_error "cannot read $dir/VERSION at $HEAD"
  new_content="$BLOB"
  old_content=""
  is_new=1
  if [ -n "${OLD_PKG[$dir]+set}" ] && object_is blob "$MERGE_BASE" "$dir/VERSION"; then
    read_blob "$MERGE_BASE" "$dir/VERSION" || usage_error "cannot read $dir/VERSION at the merge-base"
    old_content="$BLOB"
    is_new=0
  fi

  if [ "$is_new" = 0 ] && [ "$new_content" = "$old_content" ]; then
    if [ -n "${TOUCHED[$dir]+set}" ]; then
      violation version-not-bumped "$dir" "files under $dir/ changed but $dir/VERSION did not"
    elif [ "${OLD_PKG[$dir]}" != "$pkg" ] || [ "${OLD_PARENT[$dir]}" != "${NEW_PARENT[$dir]}" ]; then
      violation version-not-bumped "$dir" "the images.conf row changed but $dir/VERSION did not"
    fi
    continue
  fi
  BUMPED[$dir]=1

  if ! parse_version "$new_content"; then
    violation version-format "$dir" "$dir/VERSION must be one line matching $VERSION_RE"
    continue
  fi
  tag="$TAG"
  family="${tag%-*}"
  n="${tag##*-}"

  if [ "$is_new" = 1 ]; then
    [ "$n" = 1 ] || violation version-increment "$dir" "a new image starts at $family-1, found $tag"
  elif parse_version "$old_content" && [ "${TAG%-*}" = "$family" ]; then
    expected="$family-$(decimal_successor "${TAG##*-}")"
    [ "$tag" = "$expected" ] || violation version-increment "$dir" "expected $expected after $TAG, found $tag"
  else
    [ "$n" = 1 ] || violation version-increment "$dir" "a new family starts at $family-1, found $tag"
  fi

  status=0
  "$TAG_EXISTS" "$REGISTRY" "$pkg" "$tag" || status=$?
  case "$status" in
    0) violation tag-exists "$dir" "$REGISTRY/$pkg:$tag is already published" ;;
    1) ;;
    *)
      printf 'check-versions: error: registry check for %s/%s:%s exited %s\n' "$REGISTRY" "$pkg" "$tag" "$status" >&2
      REGISTRY_ERRORS=$((REGISTRY_ERRORS + 1))
      ;;
  esac
  PUBLISH+=("$pkg:$tag")
done

for dir in ${NEW_DIRS[@]+"${NEW_DIRS[@]}"}; do
  [ -n "${BUMPED[$dir]+set}" ] && continue
  changed_ancestors=()
  ancestor="${NEW_PARENT[$dir]}"
  while [ "$ancestor" != "-" ]; do
    [ -n "${BUMPED[$ancestor]+set}" ] && changed_ancestors+=("$ancestor")
    ancestor="${NEW_PARENT[$ancestor]}"
  done
  if [ "${#changed_ancestors[@]}" -gt 0 ]; then
    violation descendant-not-bumped "$dir" "$dir/VERSION not bumped although ancestor ${changed_ancestors[*]} changed"
  fi
done

if [ "$REGISTRY_ERRORS" -gt 0 ]; then
  exit 3
fi
if [ "$VIOLATIONS" -gt 0 ]; then
  exit 1
fi
if [ "${#PUBLISH[@]}" -gt 0 ]; then
  printf '%s\n' "${PUBLISH[@]}"
fi
exit 0
