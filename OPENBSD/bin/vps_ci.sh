#!/usr/bin/env zsh
# Run one Rails app CI on vm23 with mutex + load gate (serial operator entrypoint).
# Usage: zsh OPENBSD/bin/vps_ci.sh brgen
set -euo pipefail

usage="usage: zsh OPENBSD/bin/vps_ci.sh APP — sync APP's copy-tree, then run its bin/ci under the CI lock"
if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  print -r -- "$usage"
  exit 0
fi

app=${1:-}
[[ -n $app ]] || { print -u2 -r -- "$usage"; exit 2 }

# Validate before using the argument in any filesystem path. This entrypoint
# only runs Rails app CI; an arbitrary app string must never widen its reach.
case $app in
  brgen|bsdports) ;;
  *) print -u2 "vps_ci: unknown app \"$app\" — allowed: brgen, bsdports"; exit 2 ;;
esac

repo=${PUB4_ROOT:-/home/dev/pub4}
app_dir=/home/${app}/app
# The Gemfiles name path gems relative to the app dir (../__shared, ../brgen_*),
# so the copy-tree keeps them as siblings of app/, the layout RAILS/_deploy.sh builds.
[[ -d $app_dir ]] || { print -u2 "missing $app_dir"; exit 1 }
[[ -x /usr/local/sbin/pub4-admin ]] || { print -u2 "vps_ci: pub4-admin missing; run reviewed OPENBSD/OPERATOR.sh first"; exit 1 }

# deploy_status (from RAILS/_core.sh) -- same in-progress status file the
# SKIP_CI=1 path (_deploy.sh/_runtime_gate.sh) writes, so `bin/vps-state`
# is one place to check regardless of which deploy path is running.
[[ -f ${repo}/RAILS/_core.sh ]] && . "${repo}/RAILS/_core.sh"
command -v deploy_status >/dev/null 2>&1 || deploy_status() { :; }

export PUB4_CI_GUARD=1
export PUB4_RAILS_ROOT=${PUB4_RAILS_ROOT:-$repo/RAILS}

# Path and safe creation live in OPENBSD/lib/ci_lock.sh — the lock moved out of
# world-writable /var/tmp, where root was chmod'ing a caller-chosen, symlinkable path.
. "${repo}/OPENBSD/lib/ci_lock.sh"

# Names every tracked entry at the app root that is neither synced nor kept
# local. Warns rather than fails: this list is discovered from git at deploy
# time, so a wrong reading here would refuse a deploy for a documentation file,
# and a deploy pipeline that cries wolf gets its checks removed. Loud and
# specific is the useful setting until the set has been stable a while.
#
# Found this way: .rubocop.yml was missing and nothing said so for twelve days,
# and .ruby-version is absent from bsdports' copy-tree entirely.
unaccounted_tracked_files() {
  local app=$1 repo=$2
  local -a synced=(${(P)3}) kept=(${(P)4})
  local -a tracked missing
  tracked=(${(f)"$(git -C "$repo" ls-files "RAILS/$app" 2>/dev/null)"}) || return 0
  (( ${#tracked} )) || return 0

  local rel top
  for rel in $tracked; do
    top=${${rel#RAILS/$app/}%%/*}
    [[ -n $top ]] || continue
    # A synced entry may be a subpath — vendor/javascript covers vendor's only
    # tracked content — so a top-level name counts as accounted when any synced
    # path is it or descends from it. Without this the check reports `vendor`,
    # which is the accounting being wrong rather than the sync.
    (( ${synced[(Ie)$top]} )) && continue
    # :- is load-bearing under `set -u`. (I) yields an index and is 0 when there
    # is no match, so it is safe bare; (r) yields the matched VALUE, and a search
    # that matches nothing is an unset parameter, which nounset makes fatal. This
    # aborted every deploy's CI step with "synced[(r)$top/*]: parameter not set"
    # — the guard erroring rather than the thing it guards.
    [[ -n ${synced[(r)$top/*]:-} ]] && continue
    (( ${kept[(Ie)$top]} )) && continue
    [[ $top == *.sh || $top == *.md ]] && continue
    missing+=($top)
  done

  local -a uniq_missing=(${(u)missing})
  (( ${#uniq_missing} )) || return 0
  print -u2 "vps_ci: $app — tracked but neither synced nor kept local: ${uniq_missing}"
  print -u2 "vps_ci: $app — add each to paths (bin/ci reads the copy-tree) or to kept_local with a reason"
}

# Once installed, the broker runs the fixed synchronizer with the app UID,
# app primary group, and only the _pub4ci supplementary group. The root-copy
# code above remains only for first rollout on boxes without the broker.
sync_from_repo() {
  local -a paths=(test app lib config bin db engines public vendor/javascript
                  Gemfile Gemfile.lock config.ru Rakefile .rubocop.yml .ruby-version)
  local -a kept_local=(log storage docs script domains.yml Procfile.dev)
  unaccounted_tracked_files "$app" "$repo" paths kept_local
  doas /usr/local/sbin/pub4-admin ci-sync "$app"
}

print "vps_ci: $app (sync + mutex + load gate)"
# Establish group access and the private-storage mode before the app-owned
# synchronizer reads the checkout and updates the CI copy-tree.
pub4_ensure_ci_lock >/dev/null
doas /usr/local/sbin/pub4-admin ci-prepare "$app"
# The checkout is owned by dev, so this permission repair does not cross doas.
chmod -R u+rX,g+rX "${repo}/MASTER/tools"
deploy_status "$app" "sync tree"
sync_from_repo
deploy_status "$app" "bundle install + bin/ci"
# The brgen suite ran 59 minutes on this 1 vCPU box (coverage on) and was cut off at the
# guard's default 3600s still running, so CI gets two hours; the guard itself stays on.
ci_timeout=${PUB4_CI_TIMEOUT:-7200}
doas /usr/local/sbin/pub4-admin ci-run "$app" "$ci_timeout" \
  || { deploy_status "$app" "bundle install + bin/ci" "failed"; exit 1; }

sha=$(git -C "$repo" rev-parse --short HEAD 2>/dev/null || echo unknown)
doas /usr/local/sbin/pub4-admin stamp "$app" "$sha" ci_ok
deploy_status "$app" "done" "done"
