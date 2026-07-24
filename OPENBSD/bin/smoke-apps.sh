#!/bin/sh
# Smoke /up for inventory Rails apps + master web.
# Ports match RAILS/apps.yml (brgen 38182, amber 61352, bsdports 47312).
set -eu

fail=0
smoke() {
  name=$1
  port=$2
  if ! curl -fsS -m 8 "http://127.0.0.1:${port}/up" >/dev/null 2>&1; then
    echo "FAIL ${name} :${port}/up"
    fail=1
  else
    echo "ok   ${name} :${port}/up"
  fi
}

if curl -fsS -m 5 "http://127.0.0.1:53187/up" >/dev/null 2>&1; then
  echo "ok   master :53187/up"
else
  echo "skip master :53187/up (not listening)"
fi

smoke brgen 38182
smoke amber 61352
smoke bsdports 47312

exit "$fail"
