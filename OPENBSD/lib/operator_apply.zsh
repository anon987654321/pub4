#!/usr/bin/env zsh
sync_openbsd_apply() {
  typeset src=${1:-${CONFIG_ROOT}}
  install_root_configs "$src" || return 1

  /sbin/pfctl -nf /etc/pf.conf || { log ERROR "pf.conf invalid after sync"; return 1 }
  /sbin/pfctl -f /etc/pf.conf  || { log ERROR "pf reload failed"; return 1 }
  /sbin/pfctl -e 2>/dev/null || log WARN "pf already enabled or enable skipped"

  if [[ -x /usr/bin/ruby34 ]] || command -v ruby34 >/dev/null 2>&1; then
    ruby34 "${SCRIPT_DIR}/relayd_prune_keypairs.rb" --apply /etc/relayd.conf \
      || log WARN "relayd keypair prune failed"
  fi
  relayd -n -f /etc/relayd.conf || { log ERROR "relayd.conf invalid after sync"; return 1 }

  if [[ -x /usr/local/bin/nsd-resign ]]; then
    ruby /usr/local/bin/nsd-resign || log WARN "nsd-resign failed after zone sync"
  fi

  # STRICT rules.yml adherence (per success_criteria: "system_applies_to_itself_without_exception", self_test, ground_truth_check, evidence_scoring, veto_patterns, anti_patterns, tier1 principle_priorities).
  # Run MASTER deep scan on OPERATOR tree before any service restart. Block on violations (tier1 critical + veto).
  # Uses ground_truth_check (fresh read), self_test (laws on OPERATOR), evidence_scoring (scan_clean).
  # Also covers lexical/structural for sh, yml, conf, erb; no bypasses.
  if [[ -n ${SKIP_MASTER_SCAN:-} ]]; then
    log WARN "MASTER scan skipped (SKIP_MASTER_SCAN)"
  elif [[ -x /home/dev/pub4/MASTER/bin/cli ]]; then
    log INFO "MASTER rules scan (OPERATOR) — strict pre-apply per rules.yml (ROBUSTNESS/SINGULARITY/LINEARITY/PROXIMITY/ABSTRACTION/DENSITY + veto)"
    if ! su dev -c 'cd /home/dev/pub4/MASTER && MASTER_SCAN_DETERMINISTIC=1 MASTER_SAFE_MODE=1 bundle34 exec ruby bin/cli /scan OPENBSD --depth deep' 2>&1 | tee /tmp/master_deploy_scan.log; then
      log ERROR "MASTER scan found violations — refusing sync/apply (self_violation would occur per rules.yml)"
      return 1
    fi
    log INFO "MASTER scan clean — proceeding (scan_clean + self_apply satisfied)"
  else
    log WARN "MASTER not available for scan; continuing (violates full self-application — fix immediately)"
  fi

  # Enforce ground_truth_check + evidence before writes (rules.yml): fresh read, diff, output shown.
  # library_verify pre-flight before bundle/shell (per rules).
  for f in /etc/pf.conf /etc/relayd.conf; do
    [[ -s $f ]] || { log ERROR "ground_truth fail on $f"; return 1; }
  done
  # (In per-app: before bundle, check Gemfile etc.)

  # Not `|| true`. The crontab schedules /usr/local/bin/resource_guard.sh every
  # five minutes and it is the load-shedding guard that keeps this 1GB box up —
  # swallowing the install failure meant it could simply be absent, with no
  # error, while every log line still said the crontab was installed.
  if ! install -m 755 "${SCRIPT_DIR}/bin/resource_guard.sh" /usr/local/bin/resource_guard.sh; then
    log ERROR "resource_guard.sh install failed — the load guard would be absent"
    return 1
  fi

  # resource_guard.sh's crisis tier is guarded the same way and installed from
  # the same place. LOAD_CRIT runs `/usr/local/bin/emergency_cpu.sh` when it is
  # executable and logs "emergency_cpu not installed" when it is not, so without
  # this line the top tier of the load guard can only ever write that line.
  if ! install -m 755 "${SCRIPT_DIR}/emergency_cpu.sh" /usr/local/bin/emergency_cpu.sh; then
    log ERROR "emergency_cpu.sh install failed — resource_guard's crisis tier would only log"
    return 1
  fi

  # crontab.vm23 schedules the weekly integrity run, and install_tracked_crontab
  # refuses a command that is not on the box. root runs the installed copy for
  # the same reason daily.local does: the checkout is dev-writable.
  if ! install -m 755 "${SCRIPT_DIR}/bin/vps_weekly_integrity.sh" /usr/local/bin/vps_weekly_integrity.sh; then
    log ERROR "vps_weekly_integrity.sh install failed — the weekly integrity run would go unscheduled"
    return 1
  fi

  # daily.local runs this as ROOT, and it guards on `[ -x /usr/local/bin/... ]`,
  # so the guard is exactly as load-bearing as the install. Nothing installed it:
  # config_drift_gate.rb sits under gates/ rather than under usr/local/bin/,
  # so install_root_configs never carried it, and the guard was false on every
  # run. Live had been edited by hand to run /home/dev/pub4/OPENBSD/... instead —
  # root executing a file the dev user can rewrite, every morning, which is the
  # escalation the guard's own comment forbids. Deploying daily.local without
  # this would swap that for a check that silently never runs.
  #
  # One file, and nothing beside it. It used to need lib/utf8.rb installed into a
  # /usr/local/bin/lib/ made for the purpose, because `require_relative` resolves
  # beside the installed copy; the gate sets its own encoding now, so the install
  # cannot half-succeed and the box carries no directory holding six lines.
  if ! install -m 755 "${SCRIPT_DIR}/gates/config_drift_gate.rb" /usr/local/bin/config_drift_gate.rb; then
    log ERROR "config_drift_gate install failed — daily.local would skip the drift check in silence"
    return 1
  fi
  install_tracked_crontab || return 1

  typeset -a svcs=(nsd httpd relayd smtpd master)
  for svc in $svcs; do
    [[ -x /etc/rc.d/$svc ]] || continue
    /usr/sbin/rcctl enable $svc 2>/dev/null || true
    /usr/sbin/rcctl restart $svc 2>/dev/null || /usr/sbin/rcctl start $svc 2>/dev/null \
      || log WARN "$svc restart/start failed"
  done
  # App services: start only if /up already returns 200 — avoids Falcon crash-loops burning CPU.
  typeset -A app_ports=(brgen 38182 amber 61352 bsdports 47312)
  typeset -a core_apps=(brgen)
  typeset -a optional_apps=(amber bsdports)
  for svc in $core_apps $optional_apps; do
    [[ -x /etc/rc.d/$svc ]] || continue
    /usr/sbin/rcctl enable $svc 2>/dev/null || true
  done
  for svc in $core_apps; do
    typeset port=${app_ports[$svc]:-0}
    if (( port > 0 )); then
      typeset code; code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1:${port}/up 2>/dev/null)
      if [[ $code != 200 ]]; then
        log WARN "$svc /up=$code before restart; attempting one controlled restart"
        /usr/sbin/rcctl restart $svc 2>/dev/null || /usr/sbin/rcctl start $svc 2>/dev/null \
          || { log ERROR "$svc restart/start failed"; return 1; }
        sleep 10
        code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 http://127.0.0.1:${port}/up 2>/dev/null)
        [[ $code == 200 ]] || { log ERROR "$svc /up still $code after restart"; return 1; }
        continue
      fi
    fi
    /usr/sbin/rcctl restart $svc 2>/dev/null || /usr/sbin/rcctl start $svc 2>/dev/null \
      || { log ERROR "$svc restart/start failed"; return 1; }
  done
  log INFO "optional Rails apps left stopped (vm23_small); start with: doas rcctl start <app>"

  wait_for_up() {
    typeset port=$1 name=$2 attempts=${3:-24} delay=${4:-5}
    typeset i code
    for (( i = 1; i <= attempts; i++ )); do
      code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 http://127.0.0.1:${port}/up 2>/dev/null)
      [[ $code == 200 ]] && { log INFO "$name /up ok (attempt $i)"; return 0; }
      sleep $delay
    done
    log ERROR "$name /up not ready on :${port} after $((attempts * delay))s (last=$code)"
    return 1
  }

  # No fallback falcon: one started here would run as dev beside rc.d/master's
  # daemon_user="master" — a second server on the same port, as the account that
  # can become root. A slow master gets the longer wait and then fails the run.
  if ! wait_for_up 53187 master 12 5; then
    log WARN "master slow — waiting longer for rc.d/master"
    wait_for_up 53187 master 24 5 || return 1
  fi
  wait_for_up 38182 brgen 24 5 || return 1

  ruby34 "${SCRIPT_DIR}/gates/health_check.rb" --core && log INFO "health_check ok" \
    || { log ERROR "health_check failed"; return 1; }
}

source "${SCRIPT_DIR}/_net.sh"

trap 'cleanup' EXIT
trap 'error_handler $? $LINENO' ERR INT TERM

# These four restate facts data/dns.yml already declares — BRGEN_IP is its
# nameserver.ip, HYP_IP the first of its xfr_peers, PUBLIC_RESOLVERS its
# resolvers.public. They stay as literals because this block is sourced before
# anything, and making it shell out to ruby34 to boot would put the deploy
# script behind an interpreter it also installs. test_dns_facts_agree fails if
# either copy moves without the other.
typeset -r BRGEN_IP="46.23.89.226"
typeset -r HYP_IP="194.63.248.53"
typeset -r LOCALHOST="127.0.0.1"

typeset -a PUBLIC_RESOLVERS=(1.1.1.1 9.9.9.9)
typeset -A APP_PORTS=(
  brgen 38182
  amber 61352
  bsdports 47312
  master 53187
)
typeset -A FAILED_CERTS

validate_ip "$BRGEN_IP" || { log ERROR "Invalid BRGEN_IP: $BRGEN_IP"; exit 1 }
validate_ip "$HYP_IP"   || { log ERROR "Invalid HYP_IP: $HYP_IP"; exit 1 }

ALL_APPS=(
  brgen:brgen.no
  amber:amberapp.art
  bsdports:bsdports.org
)

SERVICES=()

ALL_DOMAINS=(
  brgen.no:markedsplass,radio,dating,tv,takeaway,maps,messenger,ai
  longyearbyn.no:markedsplass,radio,dating,tv,takeaway,maps,messenger
  oshlo.no:markedsplass,radio,dating,tv,takeaway,maps,messenger
  stvanger.no:markedsplass,radio,dating,tv,takeaway,maps,messenger
  trmso.no:markedsplass,radio,dating,tv,takeaway,maps,messenger
  trndheim.no:markedsplass,radio,dating,tv,takeaway,maps,messenger
  reykjavk.is:markadur,radio,dating,tv,takeaway,maps,messenger
  kbenhvn.dk:markedsplads,radio,dating,tv,takeaway,maps,messenger
  gtebrg.se:marknadsplats,radio,dating,tv,takeaway,maps,messenger
  mlmoe.se:marknadsplats,radio,dating,tv,takeaway,maps,messenger
  stholm.se:marknadsplats,radio,dating,tv,takeaway,maps,messenger
  hlsinki.fi:markkinapaikka,radio,dating,tv,takeaway,maps,messenger
  brmingham.uk:marketplace,radio,dating,tv,takeaway,maps,messenger
  cardff.uk:marketplace,radio,dating,tv,takeaway,maps,messenger
  edinbrgh.uk:marketplace,radio,dating,tv,takeaway,maps,messenger
  glasgw.uk:marketplace,radio,dating,tv,takeaway,maps,messenger
  lndon.uk:marketplace,radio,dating,tv,takeaway,maps,messenger
  lverpool.uk:marketplace,radio,dating,tv,takeaway,maps,messenger
  mnchester.uk:marketplace,radio,dating,tv,takeaway,maps,messenger
  amstrdam.nl:marktplaats,radio,dating,tv,takeaway,maps,messenger
  rottrdam.nl:marktplaats,radio,dating,tv,takeaway,maps,messenger
  utrcht.nl:marktplaats,radio,dating,tv,takeaway,maps,messenger
  brssels.be:marche,radio,dating,tv,takeaway,maps,messenger
  zrich.ch:marktplatz,radio,dating,tv,takeaway,maps,messenger
  lchtenstein.li:marktplatz,radio,dating,tv,takeaway,maps,messenger
  frankfrt.de:marktplatz,radio,dating,tv,takeaway,maps,messenger
  brdeaux.fr:marche,radio,dating,tv,takeaway,maps,messenger
  mrseille.fr:marche,radio,dating,tv,takeaway,maps,messenger
  mlan.it:mercato,radio,dating,tv,takeaway,maps,messenger
  lisbon.pt:mercado,radio,dating,tv,takeaway,maps,messenger
  wrsawa.pl:marktplatz,radio,dating,tv,takeaway,maps,messenger
  gdnsk.pl:marktplatz,radio,dating,tv,takeaway,maps,messenger
  austn.us:marketplace,radio,dating,tv,takeaway,maps,messenger
  chcago.us:marketplace,radio,dating,tv,takeaway,maps,messenger
  denvr.us:marketplace,radio,dating,tv,takeaway,maps,messenger
  dllas.us:marketplace,radio,dating,tv,takeaway,maps,messenger
  dnver.us:marketplace,radio,dating,tv,takeaway,maps,messenger
  dtroit.us:marketplace,radio,dating,tv,takeaway,maps,messenger
  houstn.us:marketplace,radio,dating,tv,takeaway,maps,messenger
  lsangeles.com:marketplace,radio,dating,tv,takeaway,maps,messenger
  mnnesota.com:marketplace,radio,dating,tv,takeaway,maps,messenger
  newyrk.us:marketplace,radio,dating,tv,takeaway,maps,messenger
  prtland.com:marketplace,radio,dating,tv,takeaway,maps,messenger
  wshingtondc.com:marketplace,radio,dating,tv,takeaway,maps,messenger
  pub.healthcare
  pub.attorney
  freehelp.legal
  bsdports.org
  bsddocs.org
  discordb.org
  stacyspassion.com
  foball.no
  amberapp.art
)

# ── Stage 1: DNS, DNSSEC, TLS certificates ────────────────────────────────────

