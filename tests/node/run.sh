#!/usr/bin/env bash
set -u
set -o pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "$#" -ne 2 ]; then
  printf 'usage: run.sh <image> <platform>\n' >&2
  exit 2
fi

case "$2" in
  linux/amd64) arch=amd64 node_arch=x64 ;;
  linux/arm64) arch=arm64 node_arch=arm64 ;;
  linux/arm/v7) arch=armhf node_arch=arm ;;
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
  check test "$(command -v node)" = /usr/local/bin/node
  check node -e "
const assert = require(\"node:assert\");
assert.strictEqual(process.versions.node.split(\".\")[0], \"22\");
assert.strictEqual(process.arch, process.argv[1]);
require(\"node:crypto\").createHash(\"sha256\").update(\"x\").digest(\"hex\");
require(\"node:zlib\").gzipSync(\"x\");
assert.ok(require(\"node:tls\").rootCertificates.length > 0);
" "$2"
  for tool in npm npx corepack yarn python3; do
    check test -z "$(command -v "$tool")"
  done
  check test ! -e /usr/local/lib/node_modules
  check test ! -e /usr/share/perl
  check test -z "$(dpkg-query -Wf "\${db:Status-Abbrev}\${Package}\n" perl "libperl5*" "perl-modules-5*" liberror-perl git-man 2>/dev/null | sed -n "s/^ii //p")"
  check test "$(readlink /usr/bin/stunnel)" = /usr/bin/stunnel4
  check test ! -e /etc/stunnel/stunnel.conf
  stunnel -version >/dev/null 2>&1 || { echo "not ok: stunnel -version" >&2; exit 1; }
  check openssl version >/dev/null
  check wget --version >/dev/null
  check git --version >/dev/null
  check test -x /usr/lib/git-core/git-remote-http
  for helper in git-add--interactive git-daemon git-imap-send git-http-backend git-http-push git-http-fetch git-shell scalar; do
    check test ! -e "/usr/lib/git-core/$helper"
  done
  check test ! -e /usr/local/sbin/git-smoke.sh
  check test ! -e /etc/machine-id
  check test -z "$(dpkg-query -Wf "\${db:Status-Abbrev}\${Package}\n" systemd 2>/dev/null | sed -n "s/^ii //p")"
  check test -z "$(ls -A /var/lib/apt/lists)"
  check test -z "$(ls -A /var/log)"
  check test ! -e /var/cache/ldconfig/aux-cache
' sh "$arch" "$node_arch" || exit 1

docker run --rm -i --network none --platform "$2" "$1" sh -s <"$TESTS_DIR/../node/git-smoke.sh" >/dev/null || {
  printf 'not ok: git smoke test\n' >&2
  exit 1
}
printf 'ok node %s\n' "$2"
