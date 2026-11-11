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
  . /etc/os-release
  check test "$VERSION_CODENAME" = trixie
  check test "$(dpkg --print-architecture)" = "$1"
  check test -s /etc/ssl/certs/ca-certificates.crt
  check grep -q "^path-exclude=/usr/share/man/" /etc/dpkg/dpkg.cfg.d/autonomy-slim
  check grep -q "^path-exclude=/usr/lib/\*/lib\*san.so\*" /etc/dpkg/dpkg.cfg.d/autonomy-slim
  check grep -q "^URIs: http://snapshot.debian.org/archive/debian/[0-9TZ]*$" /etc/apt/sources.list.d/debian.sources
  check test "$(grep -c "^URIs: " /etc/apt/sources.list.d/debian.sources)" = "$(grep -c "^URIs: http://snapshot.debian.org/" /etc/apt/sources.list.d/debian.sources)"
  check test -z "$(ls -A /var/lib/apt/lists)"
  check test -z "$(ls -A /var/log)"
  check test ! -e /var/cache/ldconfig/aux-cache
  check test -z "$(command -v python3)"
' sh "$arch" || exit 1
printf 'ok root %s\n' "$2"
