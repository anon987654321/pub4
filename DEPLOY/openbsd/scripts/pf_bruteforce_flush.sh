#!/bin/ksh
# CC08 / CG09: expire or flush pf bruteforce table.

MODE="${1:-expire}"
TABLE=bruteforce

case "$MODE" in
  expire)
    doas pfctl -t "$TABLE" -T expire 86400
    echo "OK: expired bruteforce entries older than 86400s"
    ;;
  flush)
    doas pfctl -t "$TABLE" -T flush
    echo "OK: flushed bruteforce table"
    ;;
  *)
    echo "usage: $0 [expire|flush]" >&2
    exit 1
    ;;
esac