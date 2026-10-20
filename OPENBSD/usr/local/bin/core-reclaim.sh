#!/bin/ksh
# Return a core app's grown resident set to the box.
#
# resource_guard.sh sheds OPTIONAL="bsdports amber" under pressure and
# restores them when it clears. It never touches CORE="master brgen", by design —
# those are the surfaces that must stay up. The consequence is that brgen's
# worker grows and nothing ever gives the memory back.
#
# Measured 2026-08-17. brgen's worker boots at 225M and had reached 355M, growing
# about 0.4M per request and never returning any of it. One restart:
#
#   before   brgen 355M   swap 1142M/1264M (91%)   free  43M
#   after    brgen 225M   swap  812M/1264M (64%)   free 249M
#
# 130M of resident set, and 330M of swap with it. That matters because the box
# was paging continuously at rest (vmstat pi 13-27/s while idle), and a page-in
# is what a visitor actually feels: amber's home measured 12.19s to first byte
# cold against 0.40s warm. On a low-traffic site nearly every visitor is the cold
# case.
#
# Install: doas cp OPENBSD/usr/local/bin/core-reclaim.sh /usr/local/bin/ &&
#          doas chmod 755 /usr/local/bin/core-reclaim.sh
# Cron (root): 40 * * * * /usr/local/bin/core-reclaim.sh >> /var/log/core-reclaim.log 2>&1

set -e

case ${1:-} in
-h|--help)
  echo "usage: /usr/local/bin/core-reclaim.sh"
  echo "  restart brgen when its RSS or swap is over the ceiling, at most hourly, never under load"
  exit 0
  ;;
esac

# Same reason resource_guard sets this: cron's PATH has no /usr/local/bin, where
# rcctl's dependencies and curl live, and everything started here inherits it.
export PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin

STATE=/var/db/core_reclaim_last

# brgen only, for now, and deliberately.
#
# master's RSS reads 42M against 927M of address space because it is almost
# entirely swapped out — RSS understates a swapped process, so the same ceiling
# would never fire for it and a VSZ ceiling would fire constantly. Restarting the
# face also drops any open TTS socket. amber and bsdports already belong to
# resource_guard; two jobs restarting one app is how they fight.
APP=brgen
PORT=38182
# Boot baseline 225M, measured above. 320M is baseline plus ~40%: high enough
# that a normal working day does not trip it, low enough that the box never
# reaches the 91% swap this was written for.
CEILING_MB=320
# Swap pressure that a restart is worth answering. The box pages continuously
# above roughly two thirds, and the first response measured 12.19s cold against
# 0.40s warm — so this is the number a visitor feels, not a tidiness figure.
SWAP_PCT_MAX=65
# A restart costs a cold boot for whoever asks next, so not during a spike and
# not more than once an hour. vm23 is 1 vCPU: load 1.0 is a busy core, not a
# crisis, so this is about avoiding a restart storm rather than about load.
LOAD_MAX=2.5
MIN_INTERVAL_S=3000

# A heartbeat, written every run, before any decision.
#
# This job logs only when it reclaims, so an empty log means either "nothing
# needed doing" or "cron stopped calling me", and those are the same silence.
# It read 12 days quiet while the box sat at 76% swap. health_check.rb reads
# this file's mtime, so the two states are now different facts.
mkdir -p /var/db 2>/dev/null || true
date +%s > /var/db/core_reclaim_seen 2>/dev/null || true

# Resident size of the process listening on a port, in KB.
#
# Was `ps -axo rss,args | grep "127.0.0.1:$PORT" | grep -v grep | head -1 |
# awk '{print $1}'`. grep, head and awk are banned in committed scripts here
# because this deploys to OpenBSD and the BSD variants break GNU idioms, and
# the pipeline was fragile on its own terms: it matched an args substring
# across every process on the box, so the answer depended on which line came
# first, and `grep -v grep` existed because the pipeline matched itself.
#
# pgrep -n -f names one pid, the newest match. Verified on vm23 against the
# old form: both returned 52020 KB for master.
rss_of_port() {
  _pid=$(pgrep -n -f "127.0.0.1:$1" 2>/dev/null) || return 0
  [[ -n "$_pid" ]] || return 0
  ps -o rss= -p "$_pid" 2>/dev/null | tr -d ' '
}

now=$(date +%s)
if [[ -r "$STATE" ]]; then
  last=$(cat "$STATE" 2>/dev/null || echo 0)
  if [[ "$(( now - last ))" -lt "$MIN_INTERVAL_S" ]]; then
    exit 0
  fi
fi

rss_kb=$(rss_of_port "$PORT")
[[ -n "$rss_kb" ]] || exit 0
rss_mb=$(( rss_kb / 1024 ))

# RSS or swap, because RSS alone could not see the case this exists for.
#
# The header above says it about master: RSS understates a swapped process. It
# is just as true of brgen. Measured 2026-09-11 — brgen resident 199M against a
# 320M ceiling, address space 877M, swap 968M/1264M — so the ceiling never
# fired, this job never reclaimed once in twelve days, and the kernel did the
# reclaiming instead: 21 `killed: out of swap` for brgen in one dmesg buffer,
# one of them relayd. A ceiling that cannot fire under pressure is not a
# ceiling; the pressure itself has to be readable.
# swapctl -l prints a Device header, then one row per device: device, blocks,
# used, avail, capacity, priority. Read with ksh itself rather than a grep,
# head, cut and tr pipeline. swap_pct is the first device's capacity and
# swap_used the used blocks of the last row, as the pipelines this replaces
# read them.
swap_pct() {
  swapctl -l 2>/dev/null | while read -r _dev _blocks _used _avail _cap _prio; do
    [[ "$_dev" = "Device" ]] && continue
    print -r -- "${_cap%\%}"
    break
  done
}
swap_used() {
  swapctl -l 2>/dev/null | {
    _last=0
    while read -r _dev _blocks _used _rest; do
      [[ "$_dev" = "Device" ]] || _last=$_used
    done
    print -r -- "$_last"
  }
}
swap_pct=$(swap_pct)
[[ -n "$swap_pct" ]] || swap_pct=0
if [[ "$rss_mb" -lt "$CEILING_MB" ]] && [[ "$swap_pct" -lt "$SWAP_PCT_MAX" ]]; then
  exit 0
fi

# Field 1 is the 1-minute average, and it is the right one here while
# resource_guard.sh takes field 2. The two ask opposite questions. The guard
# must not shed a site over a passing spike, so it wants the smoothed figure; this
# script is about to cost somebody a cold boot, so it wants to know whether the box
# is busy in this minute. Reading the same field in both would make one of them
# wrong, which is why there is no shared helper for this line.
set -- $(sysctl -n vm.loadavg)
load=$1
# ksh arithmetic is integer only, so both figures are compared as millionths.
# sysctl prints the load with two decimals and LOAD_MAX has one, so six places
# lose nothing; measured on vm23 against Ruby's Float comparison over 22
# values, from 0.00 through 99.99 and both sides of 2.5, with no disagreement.
# The fraction is read as base 10 because ksh(1) takes a leading 0 as octal,
# and 08 would not parse. It spares a ruby34 start at the one moment this job
# knows the box is short of memory.
micro() {
  _int=${1%%.*}
  _frac=
  [[ "$1" = *.* ]] && _frac=${1#*.}
  _frac="${_frac}000000"
  while (( ${#_frac} > 6 )); do _frac=${_frac%?}; done
  print -r -- "$(( 10#${_int:-0} * 1000000 + 10#$_frac ))"
}
if (( $(micro "$load") > $(micro "$LOAD_MAX") )); then
  echo "$(date '+%Y-%m-%dT%H:%M:%S') skip $APP ${rss_mb}M — load $load over $LOAD_MAX"
  exit 0
fi

swap_before=$(swap_used)
rcctl restart "$APP" >/dev/null 2>&1 || {
  echo "$(date '+%Y-%m-%dT%H:%M:%S') FAILED to restart $APP at ${rss_mb}M"
  exit 1
}
echo "$now" > "$STATE"

# Wait for it to answer before claiming success: rc.d/$APP returns once the
# process is up, which is not the same as the app serving.
sleep 10
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 45 \
       -H "Host: brgen.no" "http://127.0.0.1:$PORT/" 2>/dev/null || echo 000)
rss_after=$(rss_of_port "$PORT")
swap_after=$(swap_used)
echo "$(date '+%Y-%m-%dT%H:%M:%S') reclaimed $APP ${rss_mb}M -> $(( ${rss_after:-0} / 1024 ))M, \
swap $(( swap_before / 2048 ))M -> $(( swap_after / 2048 ))M, first response $code"
