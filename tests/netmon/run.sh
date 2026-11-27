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
  check test "$(command -v python)" = /opt/venv/bin/python
  check test "$(command -v python3)" = /opt/venv/bin/python3
  check test "$(readlink -f /opt/venv/bin/python)" = /usr/bin/python3.13
  check test -z "$(ls -A /var/lib/apt/lists)"
  check test -z "$(ls -A /var/log)"
  check test ! -e /var/cache/ldconfig/aux-cache
  check ip -V >/dev/null
  check ip link show lo >/dev/null
  check test "$(readlink -f "$(command -v iptables)")" = /usr/sbin/xtables-legacy-multi
  iptables -V | grep -q legacy || { echo "not ok: iptables is not legacy" >&2; exit 1; }
  check test -n "$(command -v udhcpc)"
  udhcpc --help 2>&1 | grep -q "^Usage: udhcpc" || { echo "not ok: udhcpc" >&2; exit 1; }
  check ps -e >/dev/null
  check python -c "
import importlib.metadata, importlib.util, sys
assert sys.version_info[:2] == (3, 13), sys.version
assert sys.prefix == \"/opt/venv\", sys.prefix
pins = {\"ifaddr\": \"0.2.0\", \"pyroute2\": \"0.9.7\", \"pyudev\": \"0.24.5\", \"zeroconf\": \"0.154.0\"}
found = {d.metadata[\"Name\"].lower(): d.version for d in importlib.metadata.distributions(path=[p for p in sys.path if p.startswith(sys.prefix)])}
assert found == pins, found
assert importlib.util.find_spec(\"pip\") is None
from pyroute2 import IPRoute, IPRSocket, NetlinkError
from zeroconf import Zeroconf, ServiceInfo, NonUniqueNameException
import ifaddr, pyudev, zeroconf._dns
assert zeroconf._dns.__file__.endswith(\".so\"), zeroconf._dns.__file__
assert pyudev.Context().sys_path == \"/sys\"
assert any(a.name == \"lo\" for a in ifaddr.get_adapters())
pyc = importlib.util.cache_from_source(pyudev.__file__)
with open(pyc, \"rb\") as f:
    assert int.from_bytes(f.read(8)[4:], \"little\") & 1, \"bytecode is not hash based\"
"
' sh "$arch" || exit 1
printf 'ok netmon %s\n' "$2"
