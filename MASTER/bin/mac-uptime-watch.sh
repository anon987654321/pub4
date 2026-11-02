#!/bin/zsh
# mac-uptime-watch -- an external vantage point for the public service surface.
#
# One invocation is one tick. State persists under ~/.pub4; launchd or cron
# may call this every five minutes. A wedged curl is bounded and stale locks
# are recovered only after the owning process is confirmed gone.

umask 077

: ${PUB4_UPTIME_HOSTS:="brgen.no amberapp.no ai.brgen.no bsdports.org"}
: ${PUB4_UPTIME_WAIVED:="bsdports.org"}
: ${PUB4_UPTIME_FAILS:=3}

STATE="$HOME/.pub4/uptime_watch.state"
LOCKDIR="$HOME/.pub4/uptime_watch.lock"
STALE_LOCK_AGE=30
LOCK_OWNED=0
STATE_TMP=""
SCRIPT_NAME=${0:t}

mkdir -p "$HOME/.pub4" 2>/dev/null || exit 1

lock_appears_live() {
  local owner process_command lock_mtime current
  owner=""
  [[ -r "$LOCKDIR/pid" ]] && owner=$(<"$LOCKDIR/pid")

  if [[ "$owner" == <-> ]] && kill -0 "$owner" 2>/dev/null; then
    process_command=$(ps -p "$owner" -o command= 2>/dev/null)
    [[ "$process_command" == *"$SCRIPT_NAME"* ]] && return 0
  fi

  # A creator may be between mkdir and writing pid. Give it a short grace
  # period; after that, an absent or dead owner is safe to reap.
  lock_mtime=$(stat -f %m "$LOCKDIR" 2>/dev/null)
  [[ "$lock_mtime" == <-> ]] || return 0
  current=$(date +%s)
  (( current - lock_mtime < STALE_LOCK_AGE ))
}

acquire_lock() {
  local attempt
  for attempt in 1 2 3; do
    if mkdir "$LOCKDIR" 2>/dev/null; then
      if print -r -- "$$" > "$LOCKDIR/pid"; then
        LOCK_OWNED=1
        return 0
      fi
      rmdir "$LOCKDIR" 2>/dev/null
      return 1
    fi

    lock_appears_live && return 1
    [[ -f "$LOCKDIR/pid" ]] && rm -f "$LOCKDIR/pid"
    rmdir "$LOCKDIR" 2>/dev/null || return 1
  done
  return 1
}

cleanup() {
  [[ -n "$STATE_TMP" ]] && rm -f "$STATE_TMP"
  if (( LOCK_OWNED )) && [[ -r "$LOCKDIR/pid" ]] && [[ "$(<"$LOCKDIR/pid")" == "$$" ]]; then
    rm -f "$LOCKDIR/pid"
    rmdir "$LOCKDIR" 2>/dev/null
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

acquire_lock || exit 0

typeset -A previous_failures
if [[ -r "$STATE" ]]; then
  while IFS=' ' read -r host previous_code previous_count; do
    [[ -n "$host" && "$previous_count" == <-> ]] || continue
    previous_failures[$host]="$previous_count"
  done < "$STATE"
fi

STATE_TMP="$STATE.new.$$"
: > "$STATE_TMP" || exit 1
alerted=0

for host in ${(z)PUB4_UPTIME_HOSTS}; do
  if [[ " ${PUB4_UPTIME_WAIVED} " == *" $host "* ]]; then
    continue
  fi

  code=$(curl -sS -m 10 -o /dev/null -w '%{http_code}' "https://$host/up" 2>/dev/null)
  [[ -z "$code" ]] && code=000

  previous=${previous_failures[$host]:-0}
  if [[ "$code" == "200" ]]; then
    if (( previous >= PUB4_UPTIME_FAILS )); then
      print -r -- "RECOVERED $host $(date '+%Y-%m-%d %H:%M:%S')" >> "$HOME/.pub4/uptime_watch.log"
      osascript -e "display notification \"$host /up is answering again\" with title \"pub4 uptime\"" >/dev/null 2>&1 || true
    fi
    print -r -- "$host 0 0" >> "$STATE_TMP"
  else
    fails=$(( previous + 1 ))
    print -r -- "$host $code $fails" >> "$STATE_TMP"
    if (( fails >= PUB4_UPTIME_FAILS )); then
      alerted=1
      if (( previous < PUB4_UPTIME_FAILS )); then
        print -r -- "DOWN $host code=$code ticks=$fails $(date '+%Y-%m-%d %H:%M:%S')" >> "$HOME/.pub4/uptime_watch.log"
        osascript -e "display notification \"$host /up down (HTTP $code, $fails ticks)\" with title \"pub4 uptime\" sound name \"Basso\"" >/dev/null 2>&1 || true
      fi
    fi
  fi
done

mv -f "$STATE_TMP" "$STATE" || exit 1
STATE_TMP=""
(( alerted )) && exit 1
exit 0
