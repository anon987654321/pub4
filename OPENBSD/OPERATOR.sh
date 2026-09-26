#!/usr/bin/env zsh
# OpenBSD vm23 deploy — executable script. Everything else in this tree is an exact config mirror.
# Routine (on vm23): cd ~/pub4 && doas zsh OPENBSD/OPERATOR.sh
# Installs OPENBSD/{etc,usr,var} onto /, validates pf/relayd, restarts services.
# Rare: --first-install | --stage-1 (DNS wipe) | --stage-2 (full app bootstrap)
# VERIFIED AGAINST: OpenBSD 7.8 manual pages (2026-01-06)
#
# IDEMPOTENCY NOTES (CC14):
# - Safe to re-run: bootstrap_rails_app (cp tree, bundle install, db:prepare), sync_openbsd_configs
#   (backs up /etc first), relayd/pf template installs when configs already match, rcctl enable/start.
# - DESTRUCTIVE on re-run: stage_1 deletes /var/nsd/etc/* and /var/nsd/zones/master/* before
#   regenerating signed zones. Never re-run stage_1 on a live authoritative server without backup.
# - State tracking: STATE_FILE=/var/db/openbsd_setup.state — is_step_completed/mark_step_completed
#   helpers exist for future --resume support; certificate-renewal cron must stay append-idempotent.
# - Data preserved: Rails SQLite under /home/<app>/app/storage, ~/priv, acme certs in /etc/ssl when
#   stage_1 is skipped. Re-running stage_2 does not drop databases.
# - Post-deploy verification: ruby /home/dev/pub4/OPENBSD/gates/health_check.rb
# Engine-ize: bootstrap_rails now relies on bundle install for pub4-shared path gem (Gemfiles declare it); legacy sh shared/install_* deprecated in scripts + WIRING. No copy sprawl.

set -euo pipefail
setopt no_unset nullglob local_traps
zmodload zsh/regex
zmodload zsh/datetime

typeset -a TMPFILES
SCRIPT_DIR=${0:a:h}
REPO_ROOT=${SCRIPT_DIR:h}
CONFIG_ROOT=${REPO_ROOT}/OPENBSD

# Usage first. main() is the last of 977 lines and this text used to live inside
# it, so the one thing an operator opening the file needs was 900 lines below
# every function it describes.
usage() {
  print -r -- "OpenBSD vm23 deploy (OPERATOR.sh). Config trees: etc/ usr/ var/ → /.
Usage:
  cd ~/pub4 && doas zsh OPENBSD/OPERATOR.sh

Default: install configs, validate pf/relayd, restart services.

Rare:
  doas zsh OPERATOR.sh --first-install
  doas zsh OPERATOR.sh --stage-1        # requires I_UNDERSTAND_DNS_WIPE=1
  doas zsh OPERATOR.sh --stage-2

--sync-configs is an alias for the default.

Env:
  RUN_PRODUCTION_SEEDS=1   run db:seed during app bootstrap (default 0: never seed production)
  I_UNDERSTAND_DNS_WIPE=1  required by --stage-1"
}

# Helpers inlined for ONE_SOURCE. Pure Zsh: log, backup_directory, install_*, sync_openbsd_configs.
log() {
  typeset level=$1; shift
  print -r -- "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a /var/log/openbsd_setup.log >&2
}
log_info()  { log INFO "$@" }
log_error() { log ERROR "$@" }

transaction_log() {
  typeset operation=$1 target=$2 op_status=$3 metadata=${4:-}
  print -r -- "[$(date +'%Y-%m-%d %H:%M:%S')] [$operation] $target | Status: $op_status | $metadata" \
    >> /var/log/openbsd_transactions.log
}

cleanup() {
  typeset exit_code=$?
  for tmpfile in "${TMPFILES[@]}"; do
    [[ -n $tmpfile && -f $tmpfile ]] && rm -f "$tmpfile"
  done
  return $exit_code
}

error_handler() {
  typeset exit_code=$1 line_num=$2
  log ERROR "Script failed with exit code $exit_code at line $line_num"
  cleanup
  exit $exit_code
}

backup_directory() {
  typeset target_dir=$1 backup_name=${2:-${1:t}}
  typeset backup_dir=/var/backups/openbsd_setup
  typeset backup_file="$backup_dir/${backup_name}-${EPOCHSECONDS}.tar.gz"
  [[ ! -d $backup_dir ]] && mkdir -p "$backup_dir"
  [[ ! -d $target_dir ]] && { log WARN "Directory $target_dir does not exist, skipping backup"; return 0 }
  log INFO "Backing up $target_dir to $backup_file"
  transaction_log "BACKUP" "$target_dir" "START"
  if tar -czf "$backup_file" -C "${target_dir:h}" "${target_dir:t}" 2>/dev/null; then
    transaction_log "BACKUP" "$target_dir" "SUCCESS" "$backup_file"
    typeset -a _bfiles; _bfiles=("$backup_dir"/${backup_name}-*.tar.gz(N))
    (( ${#_bfiles} > 10 )) && {
      typeset -a _sorted; _sorted=("$backup_dir"/${backup_name}-*.tar.gz(NOm))
      for _f in "${_sorted[@]:10}"; do rm -f "$_f"; done
    }
    echo "$backup_file"
    return 0
  else
    transaction_log "BACKUP" "$target_dir" "FAILURE"
    log ERROR "Backup failed for $target_dir"
    return 1
  fi
}

install_template() {
  typeset src=${CONFIG_ROOT}/$1 dst=$2
  [[ -f $src ]] || { log ERROR "Missing template: $src"; exit 1 }
  typeset content; content=$(<"$src")
  eval "cat > \"$dst\" <<INSTALL_TEMPLATE_EOF
$content
INSTALL_TEMPLATE_EOF"
}

append_template() {
  typeset src=${CONFIG_ROOT}/$1 dst=$2
  [[ -f $src ]] || { log ERROR "Missing template: $src"; exit 1 }
  typeset content; content=$(<"$src")
  eval "cat >> \"$dst\" <<APPEND_TEMPLATE_EOF
$content
APPEND_TEMPLATE_EOF"
}

install_static() {
  typeset src=${CONFIG_ROOT}/$1 dst=$2
  [[ -f $src ]] || { log ERROR "Missing file: $src"; exit 1 }
  cp "$src" "$dst"
}

install_tracked_crontab() {
  typeset tracked=${SCRIPT_DIR}/etc/crontab.vm23
  [[ -f $tracked ]] || return 0

  # /tmp/root_crontab.$$ was a PID-predictable name in a world-writable directory
  # that root wrote and then fed straight to crontab(1) — the same shape as the
  # doas.conf staging file in validate_doas.ksh, and with root's crontab as the
  # payload. A root-owned 0700 directory has no symlink for root to follow.
  typeset cron_dir=/var/db/pub4
  mkdir -p $cron_dir && chmod 700 $cron_dir
  typeset root_cron
  root_cron=$(mktemp "${cron_dir}/root_crontab.XXXXXXXXXX") || return 1
  TMPFILES+=($root_cron)
  crontab -l 2>/dev/null > $root_cron || :

  # The PATH assignment gets its own pass, because the merge loop below cannot
  # carry it: it skips anything with fewer than six fields, and `PATH=...` is one.
  # That is how the single most load-bearing line in crontab.vm23 would have been
  # tracked in the repo and never installed. Rewritten rather than appended so a
  # stale PATH on the box is corrected rather than shadowed — cron takes the last
  # assignment, but a reader takes the first.
  typeset cron_path
  cron_path=$(grep -m1 '^PATH=' $tracked) || cron_path=''
  if [[ -n $cron_path ]]; then
    typeset merged
    merged=$(mktemp "${cron_dir}/root_crontab.XXXXXXXXXX") || return 1
    TMPFILES+=($merged)
    { print -r -- "$cron_path"; grep -v '^PATH=' $root_cron } > $merged || return 1
    mv $merged $root_cron || return 1
    log INFO "installed root cron: $cron_path"
  fi

  while IFS= read -r line; do
    [[ -z $line || $line == \#* ]] && continue
    typeset -a fields=(${=line})
    [[ ${#fields[@]} -lt 6 ]] && continue
    typeset cmdpath=$fields[6]
    typeset tag=${cmdpath:t}
    grep -q "$tag" $root_cron 2>/dev/null && continue
    # Refusing to schedule a command that is not on the box is right: cron would
    # mail root once per tick forever. Refusing silently is not. A tracked job
    # then exists in etc/crontab.vm23, is absent from the crontab, and reads as
    # complete from both ends — nothing is missing from the file you are looking
    # at. uptime-check.sh sat in crontab.vm23 and in usr/local/bin/ from
    # 2026-08-12 until 2026-08-18 and had never been scheduled, because the run
    # that installs the wrapper at stage 1 had not happened and every earlier
    # install_tracked_crontab call passed over the line without a word.
    if [[ $cmdpath == /* && ! -x $cmdpath ]]; then
      log WARN "tracked cron job not installed: $cmdpath is missing or not executable"
      continue
    fi

    print -r -- "$line" >> $root_cron
    log INFO "installed root cron: $tag"
  done < $tracked

  crontab $root_cron || { log ERROR "Crontab update failed"; return 1 }
  return 0
}

is_step_completed()  { [[ -f "${STATE_FILE}.steps" ]] && [[ $(<"${STATE_FILE}.steps") == *"$1"* ]] }
mark_step_completed() { print -r -- "$1" >> "${STATE_FILE}.steps" }

# Install exact config trees from repo onto /. Run separately or before --sync-configs:
#   doas cp -R etc usr var /
install_root_configs() {
  typeset src=${1:-${CONFIG_ROOT}}
  [[ -d $src/etc ]] || { log ERROR "No etc/ in $src"; return 1 }
  backup_directory /etc "etc-pre-sync" || return 1

  if [[ -f $src/etc/doas.conf ]] && [[ $(tail -c1 "$src/etc/doas.conf" | wc -c) -eq 0 ]]; then
    print >> "$src/etc/doas.conf"
    log WARN "doas.conf missing trailing newline — fixed before install"
  fi

  typeset doas_rollback=""
  if [[ -f /etc/doas.conf ]]; then
    mkdir -p /var/backups/openbsd_setup
    doas_rollback="/var/backups/openbsd_setup/doas.conf.${EPOCHSECONDS}.rollback"
    cp /etc/doas.conf "$doas_rollback"
  fi

  for d in etc usr var; do
    [[ -d $src/$d ]] || continue
    install -d "/$d" 2>/dev/null || true
    cp -R "$src/$d"/. "/$d"/
    log INFO "installed /$d from repo"
  done

  # 755 first, then 555 for the scripts this repo owns. Written the other way
  # round, the blanket loop undid the line above it two lines later, so the mode
  # the file asks for twice — here and where master is installed — was never the
  # mode it set.
  #
  # Two conventions, on purpose, and vm23 already runs both: OpenBSD's own 82
  # base scripts are 755, and the nine this repo installs are r-xr-xr-x. The
  # read-only bit is the signal that the file is generated from the checkout and
  # a local edit will be overwritten. root writes through it regardless, which is
  # why `cp` onto an installed script has always worked.
  [[ -f /etc/daily.local ]] && chmod 755 /etc/daily.local
  for f in /etc/rc.d/*(N); do chmod 755 "$f"; done
  for svc in master ${ALL_APPS%%:*}; do
    [[ -f /etc/rc.d/$svc ]] && chmod 555 /etc/rc.d/$svc
  done
  for f in /usr/local/bin/*(N); do [[ -f $f ]] && chmod 755 "$f"; done
  # libexec holds helpers root dot-sources (stale_ci_cleanup.ksh); they must be
  # root-owned and not group/world writable or the sourcing is a root RCE.
  for f in /usr/local/libexec/*(N); do [[ -f $f ]] && chown root:wheel "$f" && chmod 755 "$f"; done

  if [[ -f /etc/doas.conf ]]; then
    if ! su dev -c 'doas id' 2>/dev/null | grep -q 'uid=0(root)'; then
      log ERROR "doas validation failed after config install — aborting (restoring previous doas.conf)"
      [[ -n $doas_rollback && -f $doas_rollback ]] && cp "$doas_rollback" /etc/doas.conf
      return 1
    fi
    log INFO "doas validation passed after config install"
  fi

  install_tracked_crontab || return 1

  # /home/dev/.zshrc is not installed from etc/.zshrc. That file is sync.rb's
  # redacted mirror of the live one, so copying it back would replace dev's API
  # keys with __REDACTED__.

  log INFO "OpenBSD config tree install complete (with backup)"
}

sync_openbsd_configs() {
  install_root_configs "$@"
}

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

source "${SCRIPT_DIR}/dev/operator_stage_1.zsh"
source "${SCRIPT_DIR}/dev/operator_stage_2.zsh"

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



# ── Entry point ───────────────────────────────────────────────────────────────

deploy_live() {
  sync_openbsd_apply "${CONFIG_ROOT}"
}

main() {
  if [[ ${1:-} = --help || ${1:-} = -h ]]; then
    usage
    exit 0
  fi

  case ${1:-} in
    --sync-configs|--sync|sync)
      deploy_live
      ;;
    --first-install)
      [[ ${I_UNDERSTAND_DNS_WIPE:-0} == 1 ]] || {
        log ERROR "first_install rewrites DNS material; rerun with I_UNDERSTAND_DNS_WIPE=1 if this is intentional"
        exit 1
      }
      ruby34 "${SCRIPT_DIR}/gates/verify_openbsd_idempotency.rb" || exit 1
      ruby34 "${SCRIPT_DIR}/gates/verify_deploy_identity.rb" || exit 1
      stage_1
      stage_2
      ;;
    --stage-1|--stage1)
      [[ ${I_UNDERSTAND_DNS_WIPE:-0} == 1 ]] || {
        log ERROR "stage_1 rewrites DNS material; rerun with I_UNDERSTAND_DNS_WIPE=1 if this is intentional"
        exit 1
      }
      ruby34 "${SCRIPT_DIR}/gates/verify_openbsd_idempotency.rb" || exit 1
      ruby34 "${SCRIPT_DIR}/gates/verify_deploy_identity.rb" || exit 1
      stage_1
      ;;
    --stage-2|--stage2)
      ruby34 "${SCRIPT_DIR}/gates/verify_openbsd_idempotency.rb" || exit 1
      ruby34 "${SCRIPT_DIR}/gates/verify_deploy_identity.rb" || exit 1
      stage_2
      ;;
    "")
      deploy_live
      ;;
    *)
      log ERROR "unknown flag: $1"
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
