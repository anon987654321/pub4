#!/bin/ksh
# Shed optional Rails services when vm23 is under pressure.
# Install: doas cp .../resource_guard.sh /usr/local/bin/ && doas chmod 755 /usr/local/bin/resource_guard.sh
# Cron (root): */5 * * * * /usr/local/bin/resource_guard.sh

set -e

ALL_APPS_FLAG=/var/db/pub4_all_apps
CORE="master brgen"
OPTIONAL="amber bsdports hjerterom litestream"
# vm23 is 1 vCPU (hw.ncpu=1) — load=1.0 just means the single core is fully
# busy, which is routine, not an emergency. The previous 0.85/1.20 thresholds
# were never actually reachable in testing because of the pages-free/pages-freed
# awk bug below (fixed 2026-07-10) that silently killed this script on every
# run since it was written — so they were never validated against real load.
# First real run under the fix shed all three OPTIONAL apps within a minute of
# a batch of simultaneous restarts (load spiked to ~6.9 from restart warm-up
# alone, not sustained pressure). Retuned against tonight's observed baselines:
# calm ~0.5-1.4, restart-storm transient ~3-7, genuine OOM crisis ~4.6 sustained.
LOAD_WARN=2.5
LOAD_CRIT=5.0
MEM_WARN=12
MEM_CRIT=6

load=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')
load=${load:-9.9}

mem_free_pct=100
if vmstat -s >/dev/null 2>&1; then
  pages=$(vmstat -s | awk '/pages managed/{print $1}')
  # Anchored: "pages free" is a substring of "pages freed by pagedaemon" — an
  # unanchored match pulls both lines into $free and breaks the arithmetic
  # below with a ksh parse error, silently killing this script on every run
  # (confirmed: resource-guard never once logged in this box's history).
  free=$(vmstat -s | awk '/pages free$/{print $1}')
  if [[ -n $pages && -n $free && $pages -gt 0 ]]; then
    mem_free_pct=$(( free * 100 / pages ))
  fi
fi

GUARD_REPO=${GUARD_REPO:-/home/dev/pub4}
if [[ -r ${GUARD_REPO}/OPENBSD/sh/validate_doas.ksh ]]; then
	. ${GUARD_REPO}/OPENBSD/sh/validate_doas.ksh
	install_doas_conf_from_repo "${GUARD_REPO}/OPENBSD/etc/doas.conf" resource-guard || true
fi
if [[ -f ${GUARD_REPO}/OPENBSD/stale_ci_cleanup.ksh ]]; then
  . ${GUARD_REPO}/OPENBSD/stale_ci_cleanup.ksh
  stale_ci_cleanup "$load" "$mem_free_pct"
fi

shed=0
if awk -v l="$load" -v w="$LOAD_WARN" 'BEGIN{exit !(l>=w)}'; then shed=1; fi
if [[ $mem_free_pct -lt $MEM_WARN ]]; then shed=1; fi

if [[ -f $ALL_APPS_FLAG ]]; then
  exit 0
fi

if [[ $shed -eq 1 ]]; then
  for svc in $OPTIONAL; do
    rcctl check "$svc" 2>/dev/null | grep -q '(ok)' || continue
    logger -t resource-guard "shed $svc (load=$load mem_free=${mem_free_pct}%)"
    rcctl stop "$svc" 2>/dev/null || true
  done
  pkill -f 'tts-worker --daemon' 2>/dev/null || true
fi

if awk -v l="$load" -v c="$LOAD_CRIT" 'BEGIN{exit !(l>=c)}'; then
  logger -t resource-guard "crit load=$load — running emergency_cpu"
  ksh /home/dev/pub4/OPENBSD/emergency_cpu.sh 2>&1 | logger -t resource-guard
fi

exit 0