#!/usr/bin/env bash
set -u
set -o pipefail

url=""
auth=""
prev=""
for arg in "$@"; do
  case "$arg" in
    https://*) url="$arg" ;;
  esac
  if [ "$prev" = "--header" ]; then
    case "$arg" in
      "Authorization: "*) auth="$arg" ;;
    esac
  fi
  prev="$arg"
done

case "$url" in
  */token\?*) kind=TOKEN ;;
  */manifests/*) kind=MANIFEST ;;
  *)
    printf 'fake-curl: unexpected request: %s\n' "$*" >&2
    exit 99
    ;;
esac

printf '%s\n' "$url${auth:+ $auth}" >>"$FAKE_CURL_LOG"

exit_var="FAKE_CURL_${kind}_EXIT"
status_var="FAKE_CURL_${kind}_STATUS"
body_var="FAKE_CURL_${kind}_BODY"
if [ "${!exit_var:-0}" != 0 ]; then
  printf 'curl: (%s) fake failure\n' "${!exit_var}" >&2
  exit "${!exit_var}"
fi
printf '%s\n%s' "${!body_var:-}" "${!status_var}"
