#!/bin/sh
# Thin wrapper around grok_send_legats.rb
#
# Usage:
#   ./send_legats.sh --list
#   ./send_legats.sh --dry-run 01_innovasjon_norge_master
#   ./send_legats.sh --confirm 02_trond_mohn_medical_ai
#   ./send_legats.sh --all --dry-run
#
# Requires: ruby (stdlib yaml), mutt for --confirm sends

set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$ROOT/legats/manifest.yml"
RUBY="${RUBY:-ruby}"
GROK="$ROOT/grok_send_legats.rb"

usage() {
  echo "Usage: $0 [--list|--dry-run|--confirm|--all] [application_id ...]" >&2
  exit 1
}

list_apps() {
  "$RUBY" -ryaml -e '
    m = YAML.load_file(ARGV[0])
    m["applications"].each do |a|
      next unless a["sendable"]
      printf "%-40s %s <%s>\n", a["id"], a["funder"], a["to"]
    end
  ' "$MANIFEST"
}

DRY_RUN=0
CONFIRM=0
ALL=0
ids=""

while [ $# -gt 0 ]; do
  case "$1" in
    --list) list_apps; exit 0 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --confirm) CONFIRM=1; shift ;;
    --all) ALL=1; shift ;;
    -h|--help) usage ;;
    *) ids="$ids $1"; shift ;;
  esac
done

if [ ! -f "$MANIFEST" ]; then
  echo "missing manifest — run: ruby BPLAN/build_legats.rb" >&2
  exit 1
fi

if [ "$ALL" -eq 1 ]; then
  ids="$("$RUBY" -ryaml -e 'YAML.load_file(ARGV[0])["applications"].each { |a| puts a["id"] if a["sendable"] }' "$MANIFEST")"
fi

if [ -z "$(echo "$ids" | tr -d ' ')" ]; then
  usage
fi

args=""
[ "$DRY_RUN" -eq 1 ] && args="$args --dry-run"
[ "$CONFIRM" -eq 1 ] && args="$args --confirm"

for id in $ids; do
  # shellcheck disable=SC2086
  "$RUBY" "$GROK" --id "$id" $args
done