#!/bin/ksh
# M06 / CC09: verify brgen.no PTR for 46.23.89.226 — run from VPS (not laptop).
# Set PTR via ptr4.openbsd.amsterdam per openbsd.amsterdam docs.

set -e
IP="${BRGEN_IP:-46.23.89.226}"
EXPECTED="${PTR_HOSTNAME:-brgen.no}"

ptr=$(dig +short -x "$IP" | sed 's/\.$//')
if [ "$ptr" = "$EXPECTED" ]; then
  echo "OK: PTR $IP -> $ptr"
  exit 0
fi

echo "FAIL: PTR $IP -> '${ptr:-<none>}' (expected $EXPECTED)" >&2
echo "Set via ptr4.openbsd.amsterdam from the VM console." >&2
exit 1