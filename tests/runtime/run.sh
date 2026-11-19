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
  for tool in g++ gcc make ccache ethtool curl python3; do
    check test -n "$(command -v "$tool")"
  done
  check test "$(g++ -dumpversion)" = 14
  check test "$(stat -c %a /var/run/runtime)" = 775
  check test -z "$(ls -A /var/lib/apt/lists)"
  check test -z "$(ls -A /var/log)"
  check test ! -e /var/cache/ldconfig/aux-cache
  check test -z "$(find /usr/lib -name "lib*san.so*")"

  mkdir /tmp/build
  cd /tmp/build
  export CCACHE_DIR=/tmp/ccache
  cat >plc.cpp <<EOF
#include <optional>
#include <string>
#include <thread>
#include <vector>
extern "C" int run() {
  std::vector<std::string> names;
  std::optional<int> value;
  names.emplace_back("plc");
  std::thread worker([&] { value = 41; });
  worker.join();
  return *value + static_cast<int>(names.size());
}
EOF
  cat >main.cpp <<EOF
#include <dlfcn.h>
#include <cstdio>
int main() {
  void *handle = dlopen("./libplc.so", RTLD_NOW);
  if (!handle) {
    std::puts(dlerror());
    return 1;
  }
  auto run = reinterpret_cast<int (*)()>(dlsym(handle, "run"));
  return run && run() == 42 ? 0 : 2;
}
EOF
  printf "%s\n" \
    "all: libplc.so main" \
    "%.o: %.cpp" \
    "	ccache g++ -std=c++17 -O1 -fPIC -Wall -Werror -c \$< -o \$@" \
    "libplc.so: plc.o" \
    "	g++ -shared -o \$@ \$^ -lpthread" \
    "main: main.o" \
    "	g++ -o \$@ \$^ -ldl" >Makefile
  check make -j2 >/dev/null
  check ./main
  rm ./*.o
  check make >/dev/null
  check test "$(ccache --print-stats | sed -n "s/^direct_cache_hit	//p")" = 2

  printf "%s\n" "#include <stdio.h>" "int main(void) { return puts(\"ok\") < 0; }" >hello.c
  check gcc -Wall -Werror -o hello hello.c
  check ./hello >/dev/null
' sh "$arch" || exit 1
printf 'ok runtime %s\n' "$2"
