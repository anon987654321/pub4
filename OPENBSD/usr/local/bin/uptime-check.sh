#!/bin/ksh
# Public /up only. Installed to /usr/local/bin so root cron does not exec
# the checkout. ksh shebang so cron still runs it if PATH loses /usr/local/bin.
#
# Optional apps can be waived the same way deploy-smoke does:
#   ALLOW_AMBER_DOWN=1 ALLOW_BSDPORTS_DOWN=1
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin

fail=0
check() {
	url=$1
	code=$(curl -fsS -o /dev/null -w '%{http_code}' --max-time "${UPTIME_CHECK_TIMEOUT:-20}" "$url" || print 000)
	case $code in
	2??|3??) ;;
	*)
		print -u2 "DOWN $url ($code)"
		fail=1
		;;
	esac
}

check https://brgen.no/up
check https://ai.brgen.no/up
[[ ${ALLOW_AMBER_DOWN:-0} == 1 ]] || check https://amber.brgen.no/up
[[ ${ALLOW_BSDPORTS_DOWN:-0} == 1 ]] || check https://bsdports.org/up

exit "$fail"
