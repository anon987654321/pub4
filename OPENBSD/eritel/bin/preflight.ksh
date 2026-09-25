#!/bin/ksh
set -eu

ROOT=${0%/*}/..
ROOT=$(cd "$ROOT" && pwd)

failures=0

check_command() {
  command -v "$1" >/dev/null 2>&1 || {
    print -u2 "eritel: missing command: $1"
    failures=$((failures + 1))
    return 1
  }
}

check_optional_file() {
  command=$1
  shift
  for file in "$@"; do
    if [[ -f "$file" ]]; then
      check_command "$command" || continue
      print "eritel: checking $file"
      case "$command" in
        relayd) relayd -n -f "$file" ;;
        nsd-checkconf) nsd-checkconf "$file" ;;
        acme-client) acme-client -n -f "$file" ;;
      esac
    else
      print "eritel: skip absent $file"
    fi
  done
}

check_optional_file relayd "$ROOT/etc/relayd.conf"
check_optional_file relayd "$ROOT/etc/relayd.conf.example"
check_optional_file nsd-checkconf "$ROOT/etc/nsd.conf"
check_optional_file nsd-checkconf "$ROOT/etc/nsd.conf.example"
check_optional_file acme-client "$ROOT/etc/acme-client.conf"
check_optional_file acme-client "$ROOT/etc/acme-client.conf.example"

if [[ "$failures" -ne 0 ]]; then
  print -u2 "eritel: preflight failed: $failures missing prerequisites"
  exit 1
fi

print "eritel: OpenBSD preflight complete"
