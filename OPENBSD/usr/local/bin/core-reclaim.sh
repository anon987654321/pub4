#!/bin/ksh
# Return a core app's grown resident set to the box.
#
# resource_guard.sh sheds OPTIONAL="litestream bsdports amber" under pressure and
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
# A restart costs a cold boot for whoever asks next, so not during a spike and
# not more than once an hour. vm23 is 1 vCPU: load 1.0 is a busy core, not a
# crisis, so this is about avoiding a restart storm rather than about load.
LOAD_MAX=2.5
MIN_INTERVAL_S=3000

now=$(date +%s)
if [ -r "$STATE" ]; then
  last=$(cat "$STATE" 2>/dev/null || echo 0)
  if [ $(( now - last )) -lt $MIN_INTERVAL_S ]; then
    exit 0
  fi
fi

rss_kb=$(ps -axo rss,args | grep "127.0.0.1:$PORT" | grep -v grep | head -1 | awk '{print $1}')
[ -n "$rss_kb" ] || exit 0
rss_mb=$(( rss_kb / 1024 ))
[ "$rss_mb" -ge "$CEILING_MB" ] || exit 0

load=$(sysctl -n vm.loadavg | awk '{print $1}')
over=$(echo "$load $LOAD_MAX" | awk '{print ($1 > $2) ? 1 : 0}')
if [ "$over" = "1" ]; then
  echo "$(date '+%Y-%m-%dT%H:%M:%S') skip $APP ${rss_mb}M — load $load over $LOAD_MAX"
  exit 0
fi

swap_before=$(swapctl -l | tail -1 | awk '{print $3}')
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
rss_after=$(ps -axo rss,args | grep "127.0.0.1:$PORT" | grep -v grep | head -1 | awk '{print $1}')
swap_after=$(swapctl -l | tail -1 | awk '{print $3}')
echo "$(date '+%Y-%m-%dT%H:%M:%S') reclaimed $APP ${rss_mb}M -> $(( ${rss_after:-0} / 1024 ))M, \
swap $(( swap_before / 2048 ))M -> $(( swap_after / 2048 ))M, first response $code"
