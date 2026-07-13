#!/bin/ksh
# Kill orphaned CI/scan workers when vm23 is saturated. Sourced by resource_guard.sh.
# Safe-ish: skips falcon/rc.d parents; targets test/seed/ci/cli patterns only.

stale_ci_cleanup() {
	typeset load=${1:-0}
	typeset mem_free=${2:-100}
	typeset STALE_LOAD=4.0

	awk -v l="$load" -v t="$STALE_LOAD" 'BEGIN{exit !(l>=t)}' || return 0

	logger -t resource-guard "stale-ci cleanup load=$load mem_free=${mem_free}%"

	typeset pat
	for pat in \
		'bundle34 exec bin/ci' \
		'bundle exec bin/ci' \
		'bin/rails db:seed' \
		'bin/rails test' \
		'bin/rails dartsass' \
		'ruby.*bin/cli'
	do
		pkill -f "$pat" 2>/dev/null && logger -t resource-guard "stale-ci pkill: $pat"
	done

	pkill -U dev -f 'ruby.*bin/cli' 2>/dev/null || true
}

heal_doas_conf() {
	typeset repo=${GUARD_REPO:-/home/dev/pub4}
	typeset helper="${repo}/OPERATOR/openbsd/sh/validate_doas.ksh"
	[[ -r $helper ]] || return 0
	. "$helper"
	install_doas_conf_from_repo "${repo}/OPENBSD/etc/doas.conf" resource-guard || true
}

heal_doas_conf