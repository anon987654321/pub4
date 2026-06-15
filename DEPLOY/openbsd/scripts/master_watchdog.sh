#!/bin/ksh
# CC07: restart MASTER if rcctl check fails (watchdog recovery).

if /usr/sbin/rcctl check master 2>/dev/null | grep -q '(ok)'; then
  exit 0
fi

logger -t master-watchdog "master unhealthy — attempting restart"
doas rcctl restart master
sleep 5
/usr/sbin/rcctl check master