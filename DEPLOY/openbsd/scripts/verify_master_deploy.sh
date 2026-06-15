#!/bin/ksh
# M01–M03: MASTER rc.d, master.env keys, rcctl enable — run on VPS as dev with doas.
# Tracked: DEPLOY/openbsd/scripts/verify_master_deploy.sh

set -e
REPO="${REPO:-/home/dev/pub4}"
SAMPLE="${REPO}/DEPLOY/openbsd/etc/master.env.sample"
RC_SRC="${REPO}/DEPLOY/openbsd/etc/rc.d/master"
RC_DST="/etc/rc.d/master"
ENV_DST="/etc/master.env"

fail() { echo "FAIL: $*" >&2; exit 1 }
ok() { echo "OK: $*"; }

[ -f "$RC_SRC" ] || fail "missing tracked rc.d template $RC_SRC"
[ -f "$SAMPLE" ] || fail "missing master.env.sample"

doas install -o root -g wheel -m 0755 "$RC_SRC" "$RC_DST"
ok "M01 rc.d/master installed to $RC_DST"

if [ ! -f "$ENV_DST" ]; then
  fail "M02 $ENV_DST missing — create from $SAMPLE on VPS"
fi

missing=""
while IFS= read -r key; do
  [ -z "$key" ] && continue
  grep -q "^${key}=" "$ENV_DST" 2>/dev/null || missing="${missing} ${key}"
done <<EOF
$(grep -E '^[A-Z_]+=' "$SAMPLE" | cut -d= -f1)
EOF

[ -z "$missing" ] || fail "M02 $ENV_DST missing keys:$missing"
ok "M02 master.env has all keys from sample"

doas rcctl enable master
doas rcctl check master | grep -q '(ok)' || fail "M03 master service not healthy after enable"
ok "M03 master enabled and healthy"