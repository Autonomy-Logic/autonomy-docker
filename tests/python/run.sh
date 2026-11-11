#!/usr/bin/env bash
set -u
set -o pipefail

if [ "$#" -ne 2 ]; then
  printf 'usage: run.sh <image> <platform>\n' >&2
  exit 2
fi

case "$2" in
  linux/amd64) arch=amd64 ;;
  linux/arm64) arch=arm64 ;;
  linux/arm/v7) arch=armhf ;;
  *)
    printf 'run.sh: unsupported platform: %s\n' "$2" >&2
    exit 2
    ;;
esac

docker run --rm --network none --platform "$2" "$1" sh -euc '
  check() { "$@" || { echo "not ok: $*" >&2; exit 1; }; }
  check test "$(dpkg --print-architecture)" = "$1"
  check test "$(command -v python3)" = /usr/bin/python3
  check test -n "$(ls /usr/lib/*/libpython3.13.so.1.0)"
  check test -z "$(ls -A /var/lib/apt/lists)"
  check test -z "$(ls -A /var/log)"
  check python3 -c "
import importlib.util, json, os, ssl, sqlite3, ctypes, sys, zlib
assert sys.version_info[:2] == (3, 13), sys.version
assert ssl.create_default_context().cert_store_stats()[\"x509_ca\"] > 0
pyc = importlib.util.cache_from_source(json.__file__)
with open(pyc, \"rb\") as f:
    header = f.read(16)
assert int.from_bytes(header[8:12], \"little\") == int(os.stat(json.__file__).st_mtime), \"stale bytecode\"
"
' sh "$arch" || exit 1
printf 'ok python %s\n' "$2"
