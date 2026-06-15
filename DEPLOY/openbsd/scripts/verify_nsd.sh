#!/bin/ksh
# CC13: verify NSD serves authoritative DNS for brgen.no

set -e
IP="${BRGEN_IP:-46.23.89.226}"
ZONE="${NSD_ZONE:-brgen.no}"

/usr/sbin/rcctl check nsd | grep -q '(ok)' || { echo "FAIL: nsd not running" >&2; exit 1; }

answer=$(dig @"$IP" "$ZONE" SOA +short)
[ -n "$answer" ] || { echo "FAIL: no SOA for $ZONE on $IP" >&2; exit 1; }

echo "OK: NSD authoritative for $ZONE — SOA: $answer"