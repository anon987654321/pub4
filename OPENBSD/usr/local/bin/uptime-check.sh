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
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin
# Strict on purpose: every fallible command below already carries its own
# fallback (curl || print 000), so set -e only guards the plumbing.
set -eo pipefail

PUB4_ROOT=${PUB4_ROOT:-/home/dev/pub4}
FALLBACK='brgen,https://brgen.no/up
master,https://ai.brgen.no/up
amber,https://amber.brgen.no/up
bsdports,https://bsdports.org/up'

# name,url per line. The master face is not in apps.yml — it is not a Rails app
# under /home/*/app — so its domain comes from the deploy inventory beside it.
app_targets() {
	ruby34 -ryaml -rjson -e '
	  root = ARGV[0]
	  rows = YAML.safe_load(File.read(File.join(root, "RAILS", "apps.yml")))
	            .fetch("apps")
	            .map { |name, meta| [name.to_s, meta.fetch("domain").to_s] }
	  inventory = File.join(root, "OPENBSD", "deploy_inventory.json")
	  if File.file?(inventory)
	    face = JSON.parse(File.read(inventory))["master_face"]
	    rows << [face["name"].to_s, face["domain"].to_s] if face && face["domain"]
	  end
	  rows.each { |name, domain| puts "#{name},https://#{domain}/up" }
	' "$PUB4_ROOT" 2>/dev/null
}

fail=0
check() {
	url=$1
	code=$(curl -fsS -o /dev/null -w '%{http_code}' --max-time "${UPTIME_CHECK_TIMEOUT:-20}" "$url") || code=000
	case $code in
	2??|3??) ;;
	*)
		print -u2 "DOWN $url ($code)"
		fail=1
		;;
	esac
}

targets=$(app_targets) || targets=
if [[ -z $targets ]]; then
	print -u2 "uptime-check: no app list under $PUB4_ROOT — checking the built-in names"
	targets=$FALLBACK
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

exit "$fail"
