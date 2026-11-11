#!/usr/bin/env bash
# shellcheck disable=SC2034

# Loads images.conf and every VERSION of the current directory into IMG_DIRS, IMG_PKG, IMG_PARENT and IMG_TAG.
load_images() {
  local line dir pkg parent extra tag
  IMG_DIRS=()
  declare -gA IMG_PKG=() IMG_PARENT=() IMG_TAG=()
  if [ ! -f images.conf ]; then
    printf 'images: images.conf not found in %s\n' "$PWD" >&2
    return 1
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    dir="" pkg="" parent="" extra=""
    read -r dir pkg parent extra <<<"$line"
    [ -z "$dir" ] && continue
    if [ -z "$parent" ] || [ -n "$extra" ] || ! [[ $dir =~ ^[a-z][a-z0-9-]*$ ]] || ! [[ $pkg =~ ^[a-z][a-z0-9-]*$ ]]; then
      printf 'images: invalid images.conf line: %s\n' "$line" >&2
      return 1
    fi
    if [ "$parent" != "-" ] && [ -z "${IMG_PKG[$parent]+set}" ]; then
      printf 'images: parent %s of %s is not on an earlier line\n' "$parent" "$dir" >&2
      return 1
    fi
    if ! tag="$(cat "$dir/VERSION" 2>/dev/null)" || ! [[ $tag =~ ^[a-z][a-z0-9.]*(-[a-z][a-z0-9.]*)*-[1-9][0-9]*$ ]]; then
      printf 'images: %s/VERSION is missing or invalid\n' "$dir" >&2
      return 1
    fi
    IMG_DIRS+=("$dir")
    IMG_PKG[$dir]="$pkg"
    IMG_PARENT[$dir]="$parent"
    IMG_TAG[$dir]="$tag"
  done <images.conf
}
