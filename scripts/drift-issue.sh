#!/usr/bin/env bash
set -u
set -o pipefail

if [ "$#" -ne 1 ]; then
  printf 'usage: drift-issue.sh <report-dir>\n' >&2
  exit 2
fi

readonly TITLE="Drift check: action needed"
report="$1/report.md"
flag="$1/action-needed"

if [ ! -s "$report" ] || [ ! -f "$flag" ]; then
  printf 'drift-issue: no report in %s\n' "$1" >&2
  exit 2
fi

if [ "$(cat "$flag")" != "yes" ]; then
  printf 'drift-issue: no action needed\n'
  exit 0
fi

number="$(gh issue list --state open --search "in:title \"$TITLE\"" --json number,title \
  --jq "[.[] | select(.title == \"$TITLE\")][0].number // empty")" || {
  printf 'drift-issue: cannot list the issues\n' >&2
  exit 2
}

if [ -z "$number" ]; then
  gh issue create --title "$TITLE" --body-file "$report" || exit 2
elif [[ $number =~ ^[0-9]+$ ]]; then
  gh issue comment "$number" --body-file "$report" || exit 2
else
  printf 'drift-issue: unexpected issue number: %s\n' "$number" >&2
  exit 2
fi
