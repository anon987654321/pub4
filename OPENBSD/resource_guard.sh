#!/bin/ksh
# Shed optional Rails services when vm23 is under pressure; restore them when
# pressure clears. Install: doas cp .../resource_guard.sh /usr/local/bin/ &&
# doas chmod 755 /usr/local/bin/resource_guard.sh
# Cron (root): */5 * * * * /usr/local/bin/resource_guard.sh

set -e

# Runs from root's cron, and everything it starts (rcctl -> rc.d scripts,
# emergency_cpu.sh) inherits this PATH. Cron's own PATH has no /usr/local/bin,
# which is where curl, bundle34 and ruby34 live — see rc.d/master for what that
# cost. The rc.d scripts set their own PATH now; this makes the whole chain
# independent of who invoked it.
export PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin

ALL_APPS_FLAG=/var/db/pub4_all_apps
SHED_STATE=/var/db/resource_guard_shed
CORE="master brgen"
OPTIONAL="amber bsdports litestream"
# vm23 is 1 vCPU (hw.ncpu=1) — load=1.0 just means the single core is fully
# busy, which is routine, not an emergency. Calm baseline ~0.5-1.4,
# restart-storm transient ~3-7, genuine OOM crisis ~4.6 sustained.
LOAD_WARN=2.5
LOAD_CRIT=5.0
# Recalibrated 2026-07-29 from the 916 ticks the history log had accumulated
# (2026-07-25..29), which is the dataset the note further down asked for.
# Observed: load p50=1.01 p75=1.69 p90=2.57; mem_avail p50=13 p75=24 p90=28.
# LOAD_RESTORE was 1.5, below the p50-p75 band, so restore needed the box to be
# quieter than it usually is. 2.0 sits between p50 and p75 and still stays well
# under LOAD_WARN, so shed and restore cannot chase each other.
LOAD_RESTORE=2.0
# Percent of physical RAM that must be AVAILABLE (free + buffer cache).
# History (2026-07-11): the guard originally measured vmstat's "pages free"
# alone, which excludes the OpenBSD buffer cache (~20% of RAM, reclaimable
# on demand). Any file I/O warming the cache dropped "free" below 12% while
# real available memory was fine, so the guard shed amber/bsdports
# on nearly every tick — a measurement artifact, not memory pressure. Free +
# Cache from top(1) is the honest availability signal. MEM_RESTORE > MEM_WARN
# gives hysteresis so shed/restore can't oscillate around one threshold.
#
# Recalibrated 2026-07-29 from the same 916-tick dataset. The hysteresis window
# was correct in shape but sat outside this box's operating range: median
# availability is 13%, one point above MEM_WARN, and MEM_RESTORE=20 was above
# the median entirely. Memory alone caused 334 of the 436 shed events, and the
# combined restore gate opened on 19% of ticks against shedding on 48% — so the
# drift was one-way and amber/bsdports stayed down for days rather than
# self-recovering, which is not what OPENBSD/CLAUDE.md claims. 8/14 keeps the
# same 6-point hysteresis gap, straddling p50 instead of sitting above it.
# Cost: more paging for the two optional apps. Swap is 1264M and was at 365M.
MEM_WARN=8
MEM_RESTORE=14

load=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')
load=${load:-9.9}

# Available memory percent = (Free + Cache) / physmem.
# top's Memory line: "Memory: Real: 273M/578M act/tot Free: 383M Cache: 192M Swap: 562M/1264M"
mem_avail_pct=100
total_mb=$(( $(sysctl -n hw.physmem 2>/dev/null || echo 0) / 1048576 ))
avail_mb=$(top -b -n 1 2>/dev/null | awk '
  function mb(v) {
    n = v + 0
    if (v ~ /G/) { return n * 1024 }
    if (v ~ /K/) { return n / 1024 }
    return n
  }
  /^Memory:/ {
    for (i = 1; i <= NF; i++) {
      if ($i == "Free:")  { f = mb($(i+1)) }
      if ($i == "Cache:") { c = mb($(i+1)) }
    }
    printf "%d", f + c
    exit
  }')
if [[ -n $avail_mb && $total_mb -gt 0 ]]; then
  mem_avail_pct=$(( avail_mb * 100 / total_mb ))
else
  # Fallback if top output changes shape: vmstat free pages (undercounts by
  # the buffer cache, so only trust it as a floor, never for restore).
  pages=$(vmstat -s | awk '/pages managed/{print $1}')
  free=$(vmstat -s | awk '/pages free$/{print $1}')
  if [[ -n $pages && -n $free && $pages -gt 0 ]]; then
    mem_avail_pct=$(( free * 100 / pages ))
  fi
fi

# This script runs as root from cron every 5 minutes (etc/crontab.vm23).
# It used to dot-source validate_doas.ksh and stale_ci_cleanup.ksh out of
# ${GUARD_REPO:-/home/dev/pub4} — a dev-owned git checkout — which meant write
# access to either file was root code execution within 5 minutes, entirely
# independent of doas. It also called install_doas_conf_from_repo, so the repo's
# doas.conf was copied over /etc/doas.conf on every tick and any hand-hardening
# of the live file was reverted.
#
# Root now sources only root-owned absolute paths, installed at deploy time.
# Nothing here reads from a user-writable tree.
# Hardcoded, not ${GUARD_LIBEXEC:-...}: an environment-overridable path to a
# file root dot-sources is the exact shape of the hole this replaced. Ships from
# OPENBSD/usr/local/libexec/ via OPERATOR.sh install_root_configs.
GUARD_HELPER=/usr/local/libexec/stale_ci_cleanup.ksh
if [[ -f $GUARD_HELPER ]]; then
  . $GUARD_HELPER
  stale_ci_cleanup "$load" "$mem_avail_pct"
else
  # Loud, not silent: the previous revision skipped quietly when the helper was
  # absent, so load-shedding cleanup could stop running unnoticed.
  logger -t resource-guard "stale_ci_cleanup helper missing at $GUARD_HELPER — cleanup skipped"
fi

shed=0
if awk -v l="$load" -v w="$LOAD_WARN" 'BEGIN{exit !(l>=w)}'; then shed=1; fi
if [[ $mem_avail_pct -lt $MEM_WARN ]]; then shed=1; fi

# Load-history log: LOAD_WARN/LOAD_CRIT above were set from a single evening's
# observation (itself skewed high by concurrent deploys/agent activity, not a
# calm baseline) -- recalibrating them again by guesswork would repeat the
# same mistake. This gives a real dataset (`awk '{print $4}' | sort -n` etc.)
# to recalibrate from once enough ticks have accumulated. One line/5min ==
# ~2000 lines/week; rotated weekly via newsyslog (OPENBSD/etc/newsyslog.conf).
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) load=$load mem_avail=${mem_avail_pct}% shed=$shed" \
  >> /var/log/resource_guard_history.log 2>/dev/null || true

if [[ -f $ALL_APPS_FLAG ]]; then
  exit 0
fi

if [[ $shed -eq 1 ]]; then
  for svc in $OPTIONAL; do
    if rcctl check "$svc" 2>/dev/null | grep -q '(ok)'; then
      logger -t resource-guard "shed $svc (load=$load mem_avail=${mem_avail_pct}%)"
      rcctl stop "$svc" 2>/dev/null || true
      if ! grep -qx "$svc" "$SHED_STATE" 2>/dev/null; then
        echo "$svc" >> "$SHED_STATE"
      fi
    fi
  done
  # tts-worker daemons used to be killed here too, at the same LOAD_WARN
  # tier as shedding amber/bsdports. On this box, load sits at LOAD_WARN or
  # above almost continuously (observed 3.3-6.4 over a full session, never
  # below 2.5) -- so the warm TTS socket pool was being reaped on nearly
  # every 5-minute tick, forcing every synthesis onto the slow cold-boot
  # oneshot path (fresh Ruby+Bundler+EventMachine+TLS handshake per request)
  # instead of a warm socket. TTS is core (see master's /health "tts is
  # mandatory per operator"), not optional like amber/bsdports, and the two
  # small idle tts-worker processes aren't what's driving load. Genuine
  # crisis-tier cleanup (LOAD_CRIT) below still reaps and respawns them.
fi

# Restore path: undo our own shedding once pressure has genuinely cleared.
# One service per tick — the 5-minute cron interval staggers cold boots for
# free, avoiding the simultaneous-restart memory spike that re-triggers the
# guard. Only services this script shed (tracked in SHED_STATE) and that are
# still enabled in rc.d are restored, so deliberately disabled services
# (e.g. decommissioned services) stay down.
if [[ $shed -eq 0 && -s $SHED_STATE && $mem_avail_pct -ge $MEM_RESTORE ]]; then
  if awk -v l="$load" -v r="$LOAD_RESTORE" 'BEGIN{exit !(l<r)}'; then
    restored=""
    for svc in $(cat "$SHED_STATE"); do
      if ! rcctl get "$svc" status >/dev/null 2>&1; then
        # No longer enabled — drop from state without starting it.
        restored=$svc
        break
      fi
      if rcctl check "$svc" 2>/dev/null | grep -q '(ok)'; then
        restored=$svc
        break
      fi
      logger -t resource-guard "restore $svc (load=$load mem_avail=${mem_avail_pct}%)"
      rcctl start "$svc" 2>/dev/null || true
      restored=$svc
      break
    done
    if [[ -n $restored ]]; then
      grep -vx "$restored" "$SHED_STATE" > "${SHED_STATE}.tmp" 2>/dev/null || true
      mv "${SHED_STATE}.tmp" "$SHED_STATE"
    fi
  fi
fi

if awk -v l="$load" -v c="$LOAD_CRIT" 'BEGIN{exit !(l>=c)}'; then
  logger -t resource-guard "crit load=$load — running emergency_cpu"
  ksh /home/dev/pub4/OPENBSD/emergency_cpu.sh 2>&1 | logger -t resource-guard
fi

exit 0
