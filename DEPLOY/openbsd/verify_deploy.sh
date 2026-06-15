#!/bin/ksh
# Verify OpenBSD deploy alignment (M01–M03). Run on vm23 as root:
#   doas ksh /home/dev/pub4/DEPLOY/openbsd/verify_deploy.sh
#
# Apply repo configs first:
#   doas zsh /home/dev/pub4/DEPLOY/openbsd/openbsd.sh --sync-configs

set -e

REPO=/home/dev/pub4/DEPLOY/openbsd
FAIL=0

check() {
	if eval "$1"; then
		print "ok  $2"
	else
		print "FAIL $2"
		FAIL=1
	fi
}

# M01 — rc.d/master matches repo
check "cmp -s \"$REPO/etc/rc.d/master\" /etc/rc.d/master" "M01 rc.d/master synced"
check "test -x /etc/rc.d/master" "M01 rc.d/master executable"

# M02 — /etc/master.env has every key from sample
if [ ! -f /etc/master.env ]; then
	print "FAIL M02 /etc/master.env missing"
	FAIL=1
else
	while IFS= read -r line; do
		case $line in
		''|\#*) continue ;;
		esac
		key=${line%%=*}
		check "grep -q \"^${key}=\" /etc/master.env" "M02 key ${key}"
	done < "$REPO/etc/master.env.sample"
fi

# M03 — master enabled at boot and healthy
check "/usr/sbin/rcctl enabled master 2>/dev/null" "M03 master enabled"
check "/usr/sbin/rcctl check master 2>/dev/null | grep -q 'master(ok)'" "M03 master running"

code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:53187/up 2>/dev/null || print 000)
if [ "$code" = 200 ]; then
	print "ok  M03 master /up returns 200"
else
	print "WARN M03 master /up returned $code (may need restart after recovery)"
fi

if [ "$FAIL" -ne 0 ]; then
	print "verify_deploy: FAILED"
	exit 1
fi

print "verify_deploy: all checks passed"