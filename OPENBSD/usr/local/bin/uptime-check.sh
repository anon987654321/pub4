#!/bin/ksh
# Public /up only. Installed to /usr/local/bin so root cron does not exec
# the checkout. ksh shebang so cron still runs it if PATH loses /usr/local/bin.
#
# The list is derived, not written here. RAILS/apps.yml is the feature truth,
# and a copy of it in this file names whatever the fleet held on the day it was
# typed — a fifth app ships and this keeps checking four, with nothing to say
# so. OPENBSD/bin/uptime-check.sh answers the same question by running
# health_check.rb, and it is not what cron gets: root would be executing a file
# the dev user can rewrite, which is the escalation this installed copy exists
# to close. Reading is the half that is safe, so this reads apps.yml as data
# through a system interpreter and never runs anything from the checkout.
#
# The names below are the fallback for a box with no checkout to read.
#
# Optional apps can be waived the same way deploy-smoke does:
#   ALLOW_AMBER_DOWN=1 ALLOW_BSDPORTS_DOWN=1
# UPTIME_PATH_PREFIX lets the test put fake curl, ruby34 and logger first.
PATH=${UPTIME_PATH_PREFIX:+$UPTIME_PATH_PREFIX:}/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
# Strict on purpose: every fallible command below already carries its own
# fallback (curl || print 000), so set -e only guards the plumbing.
set -eo pipefail

fail=0
down=
PUB4_ROOT=${PUB4_ROOT:-/home/dev/pub4}
FALLBACK='brgen,https://brgen.no/up
master,https://ai.brgen.no/up
amber,https://amberapp.art/up
bsdports,https://bsdports.org/up'

# name,url per line, master's ai.brgen.no among them.
app_targets() {
  ruby34 -ryaml -e '
    root = ARGV[0]
    rows = YAML.safe_load(File.read(File.join(root, "RAILS", "apps.yml")))
              .fetch("apps")
              .map { |name, meta| [name.to_s, meta.fetch("domain").to_s] }
    rows.each { |name, domain| puts "#{name},https://#{domain}/up" }
  ' "$PUB4_ROOT" 2>/dev/null
}

check() {
  url=$1
  code=$(curl -fsS -o /dev/null -w '%{http_code}' --max-time "${UPTIME_CHECK_TIMEOUT:-20}" "$url") || code=000
  case $code in
  2??|3??) ;;
  *)
    print -u2 "DOWN $url ($code)"
    fail=1
    down="$down $url"
    ;;
  esac
}

# Falling back is a finding, not a quiet substitution. The built-in names are
# still checked — knowing those four are up is worth more than checking nothing —
# but the run exits nonzero whatever they answer, because this script cannot then
# tell you a fifth app exists and is down. A green uptime check measuring a fleet
# that is one deploy out of date is the failure the header at the top describes.
targets=$(app_targets) || targets=
if [[ -z $targets ]]; then
  print -u2 "uptime-check: FAIL — no app list under $PUB4_ROOT, so the fleet is unknown."
  print -u2 "uptime-check: checking the built-in names anyway; this exit code is the missing list, not them."
  targets=$FALLBACK
  fail=1
fi

# A for loop, not a pipe: pdksh runs the last stage of a pipeline in a subshell,
# and `fail` set there would never reach the exit below.
for row in $targets; do
  name=${row%%,*}
  url=${row#*,}
  case $name in
  amber)    if [[ ${ALLOW_AMBER_DOWN:-0} == 1 ]]; then continue; fi ;;
  bsdports) if [[ ${ALLOW_BSDPORTS_DOWN:-0} == 1 ]]; then continue; fi ;;
  esac
  check "$url"
done

# cron sends this job's output to /var/log/uptime-check.log, which nothing reads
# unprompted; one syslog line puts a failure where an operator will see it.
#
# One failed tick can be a deploy restarting an app. A failure that survives
# UPTIME_ALERT_AFTER consecutive ticks (three, fifteen minutes) is not, and gets a
# durable pub4-alert record that says which URLs and what to read. A passing tick
# resets the count. The count lives in /var/db/pub4, root's.
failstate=${UPTIME_FAIL_STATE:-/var/db/pub4/uptime_fail_count}
alert=${PUB4_ALERT:-/usr/local/bin/pub4-alert}
n=0
after=${UPTIME_ALERT_AFTER:-3}
if [[ $fail != 0 ]]; then
	logger -t uptime-check "a public endpoint is down - see /var/log/uptime-check.log"
	[[ -f $failstate ]] && { read n < "$failstate" || n=0; }
	case $n in *[!0-9]*|'') n=0 ;; esac
	n=$(( n + 1 ))
	print -r -- "$n" > "$failstate" 2>/dev/null || true
	if (( n >= after )) && [[ -x $alert ]]; then
		"$alert" raise uptime-down "down for $n consecutive checks:$down - on the box: doas rcctl check brgen amber bsdports master relayd; ls /home/dev/pub4/.deploying-* (a deploy in flight); /var/log/uptime-check.log"
	fi
else
	print -r -- 0 > "$failstate" 2>/dev/null || true
fi

exit "$fail"
