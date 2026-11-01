#!/bin/zsh
# mac-uptime-watch -- a second vantage point that is not vm23 and not cron-on-vm23.
#
#   runs on:  the operator's Mac (launchd or cron, every 5 minutes, single shot)
#   state:    ~/.pub4/uptime_watch.state
#
# Why it exists. box-heartbeat.sh covers "the box stopped talking". This script
# covers the inverse failure: the box says everything is fine while a public
# surface is not reachable the way a visitor reaches it -- relayd answering,
# an app port closed, a DNS or registrar problem, or TLS that terminates
# somewhere unexpected. The box's own uptime-check.sh cannot see these from
# inside; a poll from the operator's network can.
#
# This mirrors OPENBSD/bin/uptime-check.sh's contract rather than re-inventing
# it: public HTTPS /up only, no vm23 tools, and the same waiver idea for a
# domain that cannot pass today (bsdports.org parked at the registrar -- the
# box carries ALLOW_BSDPORTS_DOWN=1 for the same reason). Drop the waiver the
# day delegation returns, here and in crontab.vm23, in the same commit.
#
# cron line on the Mac:
#   */5 * * * * /usr/local/bin/mac-uptime-watch.sh >> /tmp/pub4_uptime_watch.log 2>&1
# or launchd with StartInterval=300. One invocation = one tick (their idiom),
# so state persists between ticks in the state file.

: ${PUB4_UPTIME_HOSTS:="brgen.no amberapp.no ai.brgen.no bsdports.org"}
: ${PUB4_UPTIME_WAIVED:="bsdports.org"}     # ALLOW_BSDPORTS_DOWN equivalent
: ${PUB4_UPTIME_FAILS:=3}                   # 3 consecutive ticks == 15 minutes, same as the box
STATE="$HOME/.pub4/uptime_watch.state"
LOCKDIR="$HOME/.pub4/uptime_watch.lock"

mkdir -p "$HOME/.pub4" 2>/dev/null
# One instance at a time; a wedged curl must not stack ticks.
mkdir "$LOCKDIR" 2>/dev/null || exit 0
trap 'rmdir "$LOCKDIR" 2>/dev/null' EXIT
touch "$STATE" 2>/dev/null || exit 0

now=$(date +%s)
new="$STATE.new"
: >"$new"
alerted=0

for host in ${(z)PUB4_UPTIME_HOSTS}; do
  if [[ " ${PUB4_UPTIME_WAIVED} " == *" $host "* ]]; then
    continue
  fi

  code=$(curl -sS -m 10 -o /dev/null -w '%{http_code}' "https://$host/up" 2>/dev/null)
  # curl -w already prints 000 on a failed connect; only a missing curl
  # yields empty, and that is also "cannot pass right now".
  [[ -z "$code" ]] && code=000

  if [[ "$code" == "200" ]]; then
    prev=$(grep "^$host " "$STATE" 2>/dev/null | tail -n 1)
    if [[ -n "$prev" ]] && [[ $(print -r -- "$prev" | awk '{print $3}') -ge $PUB4_UPTIME_FAILS ]]; then
      print -r -- "RECOVERED $host $(date '+%Y-%m-%d %H:%M:%S')" >> "$HOME/.pub4/uptime_watch.log"
      osascript -e "display notification \"$host /up is answering again\" with title \"pub4 uptime\"" >/dev/null 2>&1 || true
    fi
    print -r -- "$host 0 0" >> "$new"
  else
    prev=$(grep "^$host " "$STATE" 2>/dev/null | tail -n 1)
    fails=1
    if [[ -n "$prev" ]]; then
      fails=$(( $(print -r -- "$prev" | awk '{print $3}') + 1 ))
    fi
    print -r -- "$host $code $fails" >> "$new"
    if (( fails >= PUB4_UPTIME_FAILS )); then
      alerted=1
      print -r -- "DOWN $host code=$code ticks=$fails $(date '+%Y-%m-%d %H:%M:%S')" >> "$HOME/.pub4/uptime_watch.log"
      osascript -e "display notification \"$host /up down (HTTP $code, $fails ticks)\" with title \"pub4 uptime\" sound name \"Basso\"" >/dev/null 2>&1 || true
    fi
  fi
done

mv "$new" "$STATE"
(( alerted )) && exit 1   # non-zero for cron mail, without being noisy per tick
exit 0
