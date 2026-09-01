#!/usr/bin/env zsh
# OpenBSD vm23 deploy — executable script. Everything else in this tree is an exact config mirror.
# Routine (on vm23): cd ~/pub4 && doas zsh OPENBSD/OPERATOR.sh
# Installs OPENBSD/{etc,usr,var} onto /, validates pf/relayd, restarts services.
# Rare: --first-install | --stage-1 (DNS wipe) | --stage-2 (full app bootstrap)
# VERIFIED AGAINST: OpenBSD 7.8 manual pages (2026-01-06)
#
# IDEMPOTENCY NOTES (CC14):
# - Safe to re-run: bootstrap_rails_app (cp tree, bundle install, db:migrate), sync_openbsd_configs
#   (backs up /etc first), relayd/pf template installs when configs already match, rcctl enable/start.
# - DESTRUCTIVE on re-run: stage_1 deletes /var/nsd/etc/* and /var/nsd/zones/master/* before
#   regenerating signed zones. Never re-run stage_1 on a live authoritative server without backup.
# - State tracking: STATE_FILE=/var/db/openbsd_setup.state — is_step_completed/mark_step_completed
#   helpers exist for future --resume support; certificate-renewal cron must stay append-idempotent.
# - Data preserved: Rails SQLite under /home/<app>/app/storage, ~/priv, acme certs in /etc/ssl when
#   stage_1 is skipped. Re-running stage_2 does not drop databases.
# - Post-deploy verification: ruby /home/dev/pub4/OPENBSD/health_check.rb
# Engine-ize: bootstrap_rails now relies on bundle install for pub4-shared path gem (Gemfiles declare it); legacy sh shared/install_* deprecated in scripts + WIRING. No copy sprawl.

set -euo pipefail
setopt no_unset nullglob local_traps
zmodload zsh/regex
zmodload zsh/datetime

typeset -a TMPFILES
SCRIPT_DIR=${0:a:h}
REPO_ROOT=${SCRIPT_DIR:h}
CONFIG_ROOT=${REPO_ROOT}/OPENBSD

# Helpers inlined ( _lib.sh removed for ONE_SOURCE/singularity). Pure Zsh: log, backup_directory, install_*, sync_openbsd_configs (now ships .zshrc to /home/dev too).
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

  [[ -f /etc/rc.d/master ]] && chmod 555 /etc/rc.d/master
  [[ -f /etc/daily.local ]] && chmod 755 /etc/daily.local
  for f in /etc/rc.d/*(N); do chmod 755 "$f"; done
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

  if [[ -f $src/etc/.zshrc ]]; then
    install -d -o dev -g dev -m 700 /home/dev 2>/dev/null || true
    cp "$src/etc/.zshrc" /home/dev/.zshrc
    chown dev:dev /home/dev/.zshrc 2>/dev/null || true
    chmod 600 /home/dev/.zshrc 2>/dev/null || true
    log INFO "synced .zshrc to /home/dev"
  fi

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
    ruby34 "${SCRIPT_DIR}/relayd_prune_keypairs.rb" /etc/relayd.conf \
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
    if ! su dev -c 'cd /home/dev/pub4/MASTER && MASTER_SCAN_ONLY=1 MASTER_SAFE_MODE=1 bundle34 exec ruby bin/cli /scan OPENBSD --depth deep' 2>&1 | tee /tmp/master_deploy_scan.log; then
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
  if ! install -m 755 "${SCRIPT_DIR}/resource_guard.sh" /usr/local/bin/resource_guard.sh; then
    log ERROR "resource_guard.sh install failed — the load guard would be absent"
    return 1
  fi

  # daily.local runs this as ROOT, and it guards on `[ -x /usr/local/bin/... ]`,
  # so the guard is exactly as load-bearing as the install. Nothing installed it:
  # config_drift_gate.rb sits at the repo root rather than under usr/local/bin/,
  # so install_root_configs never carried it, and the guard was false on every
  # run. Live had been edited by hand to run /home/dev/pub4/OPENBSD/... instead —
  # root executing a file the dev user can rewrite, every morning, which is the
  # escalation the guard's own comment forbids. Deploying daily.local without
  # this would swap that for a check that silently never runs.
  #
  # lib/utf8.rb goes too: the script's `require_relative "lib/utf8"` resolves
  # beside itself, so the installed copy is only self-contained with it there.
  install -d -m 755 /usr/local/bin/lib
  if ! install -m 755 "${SCRIPT_DIR}/config_drift_gate.rb" /usr/local/bin/config_drift_gate.rb ||
     ! install -m 644 "${SCRIPT_DIR}/lib/utf8.rb" /usr/local/bin/lib/utf8.rb; then
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
  typeset -a optional_apps=(amber bsdports litestream)
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

  if ! wait_for_up 53187 master 12 5; then
    log WARN "master slow — starting dev tmux falcon fallback"
    su -m dev -c 'tmux kill-session -t falcon53187 2>/dev/null; tmux new -d -s falcon53187 "cd /home/dev/pub4/MASTER/web && export RAILS_ENV=production MASTER_SAFE_MODE=1 MASTER_SKIP_SELF_TEST=1 MASTER_BACKGROUND=0 SECRET_KEY_BASE_DUMMY=1 PATH=/usr/local/bin:/usr/bin:/bin && exec bundle34 exec falcon serve -n 1 --health-check-timeout 300 --bind http://127.0.0.1:53187 >> /tmp/falcon53187.log 2>&1"'
    wait_for_up 53187 master 24 5 || return 1
  fi
  wait_for_up 38182 brgen 24 5 || return 1

  ruby34 "${SCRIPT_DIR}/health_check.rb" --core && log INFO "health_check ok" \
    || { log ERROR "health_check failed"; return 1; }
}

source "${SCRIPT_DIR}/_net.sh"

trap 'cleanup' EXIT
trap 'error_handler $? $LINENO' ERR INT TERM

typeset -r BRGEN_IP="46.23.89.226"
typeset -r HYP_IP="194.63.248.53"
typeset -r LOCALHOST="127.0.0.1"
typeset -r EMAIL_ADDRESS="bergen@pub.attorney"

typeset -a PUBLIC_RESOLVERS=(8.8.8.8 1.1.1.1 9.9.9.9)
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
  amber:amber.brgen.no
  bsdports:bsdports.org
)

SERVICES=()

ALL_DOMAINS=(
  brgen.no:markedsplass,playlist,dating,tv,takeaway,maps,messenger,ai
  longyearbyn.no:markedsplass,playlist,dating,tv,takeaway,maps,messenger
  oshlo.no:markedsplass,playlist,dating,tv,takeaway,maps,messenger
  stvanger.no:markedsplass,playlist,dating,tv,takeaway,maps,messenger
  trmso.no:markedsplass,playlist,dating,tv,takeaway,maps,messenger
  trndheim.no:markedsplass,playlist,dating,tv,takeaway,maps,messenger
  reykjavk.is:markadur,playlist,dating,tv,takeaway,maps,messenger
  kbenhvn.dk:markedsplads,playlist,dating,tv,takeaway,maps,messenger
  gtebrg.se:marknadsplats,playlist,dating,tv,takeaway,maps,messenger
  mlmoe.se:marknadsplats,playlist,dating,tv,takeaway,maps,messenger
  stholm.se:marknadsplats,playlist,dating,tv,takeaway,maps,messenger
  hlsinki.fi:markkinapaikka,playlist,dating,tv,takeaway,maps,messenger
  brmingham.uk:marketplace,playlist,dating,tv,takeaway,maps,messenger
  cardff.uk:marketplace,playlist,dating,tv,takeaway,maps,messenger
  edinbrgh.uk:marketplace,playlist,dating,tv,takeaway,maps,messenger
  glasgw.uk:marketplace,playlist,dating,tv,takeaway,maps,messenger
  lndon.uk:marketplace,playlist,dating,tv,takeaway,maps,messenger
  lverpool.uk:marketplace,playlist,dating,tv,takeaway,maps,messenger
  mnchester.uk:marketplace,playlist,dating,tv,takeaway,maps,messenger
  amstrdam.nl:marktplaats,playlist,dating,tv,takeaway,maps,messenger
  rottrdam.nl:marktplaats,playlist,dating,tv,takeaway,maps,messenger
  utrcht.nl:marktplaats,playlist,dating,tv,takeaway,maps,messenger
  brssels.be:marche,playlist,dating,tv,takeaway,maps,messenger
  zrich.ch:marktplatz,playlist,dating,tv,takeaway,maps,messenger
  lchtenstein.li:marktplatz,playlist,dating,tv,takeaway,maps,messenger
  frankfrt.de:marktplatz,playlist,dating,tv,takeaway,maps,messenger
  brdeaux.fr:marche,playlist,dating,tv,takeaway,maps,messenger
  mrseille.fr:marche,playlist,dating,tv,takeaway,maps,messenger
  mlan.it:mercato,playlist,dating,tv,takeaway,maps,messenger
  lisbon.pt:mercado,playlist,dating,tv,takeaway,maps,messenger
  wrsawa.pl:marktplatz,playlist,dating,tv,takeaway,maps,messenger
  gdnsk.pl:marktplatz,playlist,dating,tv,takeaway,maps,messenger
  austn.us:marketplace,playlist,dating,tv,takeaway,maps,messenger
  chcago.us:marketplace,playlist,dating,tv,takeaway,maps,messenger
  denvr.us:marketplace,playlist,dating,tv,takeaway,maps,messenger
  dllas.us:marketplace,playlist,dating,tv,takeaway,maps,messenger
  dnver.us:marketplace,playlist,dating,tv,takeaway,maps,messenger
  dtroit.us:marketplace,playlist,dating,tv,takeaway,maps,messenger
  houstn.us:marketplace,playlist,dating,tv,takeaway,maps,messenger
  lsangeles.com:marketplace,playlist,dating,tv,takeaway,maps,messenger
  mnnesota.com:marketplace,playlist,dating,tv,takeaway,maps,messenger
  newyrk.us:marketplace,playlist,dating,tv,takeaway,maps,messenger
  prtland.com:marketplace,playlist,dating,tv,takeaway,maps,messenger
  wshingtondc.com:marketplace,playlist,dating,tv,takeaway,maps,messenger
  pub.healthcare
  pub.attorney
  freehelp.legal
  bsdports.org
  bsddocs.org
  discordb.org
  stacyspassion.com
  foball.no
  amber.brgen.no
)

# ── Stage 1: DNS, DNSSEC, TLS certificates ────────────────────────────────────

stage_1() {
  log INFO "Stage 1: DNS and certificates"

  typeset -a _df_root; _df_root=("${(@f)$(df -k /)}"); typeset _root_avail=${${(z)_df_root[2]}[4]}
  (( _root_avail < 10000 )) && { log ERROR "Insufficient disk space on /"; exit 1 }
  typeset -a _df_var; _df_var=("${(@f)$(df -k /var)}"); typeset _var_avail=${${(z)_df_var[2]}[4]}
  (( _var_avail < 512000 )) && { log ERROR "Insufficient disk space on /var"; exit 1 }

  # ffmpeg is required, not optional: lib/voice/engines.rb gates concat_mp3 and
  # the WAV->MP3 conversion on `ffmpeg?` and returns *quietly* when it is absent.
  # Without it TTS produced un-concatenated or unconverted audio on the VPS with
  # no error anywhere — working on a Mac and silently degrading in production,
  # which is the worst failure shape. See TODO.md "Host TTS Binaries".
  pkg_add -U ldns-utils ruby%3.4 zap zsh fish neovim tmux fontconfig fzf ripgrep fd espeak ffmpeg 2>/tmp/pkg_add.log \
    || { log ERROR "pkg_add failed. See /tmp/pkg_add.log"; exit 1 }

  [[ -f /etc/rc.conf.local && $(<"/etc/rc.conf.local") == *"pf=NO"* ]] && log WARN "pf disabled in rc.conf.local"
  ifconfig vio0 >/dev/null 2>&1 || { log ERROR "Interface vio0 not found"; exit 1 }

  /sbin/pfctl -d || log WARN "pf disable failed"
  /sbin/pfctl -e || { log ERROR "pf enable failed"; exit 1 }
  install_static etc/pf.stage1.conf /etc/pf.conf
  /sbin/pfctl -nf /etc/pf.conf || { log ERROR "pf.conf invalid"; exit 1 }
  /sbin/pfctl -f /etc/pf.conf  || { log ERROR "pf failed"; exit 1 }

  [[ -d /var/nsd/etc ]]          || { log ERROR "/var/nsd/etc missing"; exit 1 }
  [[ -d /var/nsd/zones/master ]] || { log ERROR "/var/nsd/zones/master missing"; exit 1 }

  backup_directory /var/nsd/zones/master nsd-zones || { log ERROR "Backup failed"; exit 1 }
  transaction_log "DELETE" "/var/nsd/etc/*" "START"
  rm -rf /var/nsd/etc/*(/) /var/nsd/zones/master/*(/) # scan: intentional — backed up above, bracketed by transaction_log DELETE
  transaction_log "DELETE" "/var/nsd/etc/* and /var/nsd/zones/master/*" "SUCCESS"

  # nsd.conf and every zone file are generated by bin/render_dns.rb and committed,
  # so this installs them rather than rebuilding them from a template per domain.
  # The old loop was the third writer of the same records and disagreed with the
  # other two: it emitted no www, no CAA, no SPF, no DMARC and an MX pointing at
  # a mail server that exists for one domain out of sixty.
  install_static var/nsd/etc/nsd.conf /var/nsd/etc/nsd.conf
  nsd-checkconf /var/nsd/etc/nsd.conf || { log ERROR "nsd.conf invalid"; exit 1 }

  cp ${CONFIG_ROOT}/var/nsd/zones/master/*.zone /var/nsd/zones/master/

  for domain_entry in $ALL_DOMAINS; do
    typeset domain=${domain_entry%%:*}
    typeset zonefile=/var/nsd/zones/master/$domain.zone

    [[ -f $zonefile ]] || { log ERROR "No generated zone for $domain — run bin/render_dns.rb"; exit 1 }
    nsd-checkzone "$domain" "$zonefile" || { log ERROR "Zone invalid for $domain"; exit 1 }

    # Keys only when the zone has none.
    #
    # This unconditionally ran ldns-keygen twice per domain per invocation and
    # never removed anything, so every re-run added a KSK and a ZSK to each zone
    # and the old ones stayed published — ldns-signzone signs with every key it
    # is handed. Measured 2026-08-12: 700 key files for 60 zones, and 407 .ds
    # files naming keys that had long since been superseded.
    #
    # Regenerating a KSK is not a harmless extra file once a DS record is
    # published. The DS at the registrar names one key by tag; sign with a new
    # KSK and every validating resolver SERVFAILs the entire zone until the
    # registrar catches up. So the rule is: generate only what is missing, and
    # rotate deliberately, never as a side effect of re-running the installer.
    typeset -a existing
    existing=(/var/nsd/zones/master/K${domain}.+*.key(N))
    if (( ${#existing} == 0 )); then
      log INFO "generating DNSSEC keys for $domain"
      ( cd /var/nsd/zones/master && ldns-keygen -a ECDSAP256SHA256 "$domain" >/dev/null )
      ( cd /var/nsd/zones/master && ldns-keygen -k -a ECDSAP256SHA256 "$domain" >/dev/null )
    fi
  done

  chown _nsd:_nsd /var/nsd/zones/master/*
  chmod 640 /var/nsd/zones/master/*

  # One signing implementation, not two. nsd-resign is what runs every night; if
  # it can sign the fleet, so can a first install, and there is no second code
  # path to drift. It also picks exactly one KSK and one ZSK per zone, which is
  # the behaviour the loop above was missing.
  ruby /usr/local/bin/nsd-resign --force || { log ERROR "zone signing failed"; exit 1 }

  for domain_entry in $ALL_DOMAINS; do
    typeset domain=${domain_entry%%:*}
    nsd-checkzone "$domain" /var/nsd/zones/master/$domain.zone.signed \
      || { log ERROR "Signed zone invalid for $domain"; exit 1 }
  done

  # DS records are derived from the signed zone by bin/ds-records, never written
  # to a .ds file here. A cached DS goes stale the moment a key rotates, and a DS
  # naming a key the zone no longer publishes takes the zone down.
  log INFO "DS records: doas ruby34 ${REPO_ROOT}/OPENBSD/bin/ds-records"

  [[ ! -f /var/nsd/etc/nsd_server.pem ]] && {
    log INFO "Generating NSD control certificates"
    cd /var/nsd/etc && nsd-control-setup || { log ERROR "nsd-control-setup failed"; exit 1 }
  }

  cleanup_nsd
  /usr/sbin/rcctl enable nsd

  typeset retries=0 max_retries=2
  while (( retries <= max_retries )); do
    /usr/bin/timeout 10 /usr/sbin/rcctl start nsd && break
    (( retries++ ))
    (( retries <= max_retries )) && cleanup_nsd || { log ERROR "nsd failed"; exit 1 }
  done

  sleep 5
  typeset _nsd_check; _nsd_check=$(/usr/sbin/rcctl check nsd)
  [[ $_nsd_check == *"nsd(ok)"* ]] || { log ERROR "nsd not running"; exit 1 }
  verify_nsd

  [[ -d /var/www/acme ]] || mkdir -p /var/www/acme
  install_static etc/httpd.conf /etc/httpd.conf
  httpd -n -f /etc/httpd.conf || { log ERROR "httpd.conf invalid"; exit 1 }
  /usr/sbin/rcctl enable httpd
  /usr/sbin/rcctl start httpd || { log ERROR "httpd failed"; exit 1 }
  sleep 5
  typeset _httpd_check; _httpd_check=$(/usr/sbin/rcctl check httpd)
  [[ $_httpd_check == *"httpd(ok)"* ]] || { log ERROR "httpd not running"; exit 1 }

  # httpd strips /.well-known/acme-challenge/ and serves from /var/www/acme/<token>
  print -r -- test > /var/www/acme/test
  typeset http_status=${$(curl -s -o /dev/null -w "%{http_code}" http://$BRGEN_IP/.well-known/acme-challenge/test):-000}
  rm -f /var/www/acme/test
  [[ $http_status == "200" ]] || { log ERROR "httpd pre-flight failed (HTTP $http_status)"; exit 1 }

  [[ $(<"/etc/group") == *$'\n_acme:'* || $(<"/etc/group") == _acme:* ]] || groupadd -g 765 _acme
  [[ ! -f /etc/acme/letsencrypt_privkey.pem ]] && \
    openssl genpkey -algorithm RSA -out /etc/acme/letsencrypt_privkey.pem -pkeyopt rsa_keygen_bits:4096
  chown root:_acme /etc/acme/letsencrypt_privkey.pem
  chmod 640 /etc/acme/letsencrypt_privkey.pem

  install_static etc/acme-client.conf /etc/acme-client.conf
  acme-client -n -f /etc/acme-client.conf || { log ERROR "acme-client.conf invalid"; exit 1 }

  for domain_entry in $ALL_DOMAINS; do
    typeset domain=${domain_entry%%:*}
    typeset dns_check=${$(/usr/bin/dig @"$BRGEN_IP" "$domain" A +short):-}
    if [[ $dns_check != $BRGEN_IP ]]; then
      log WARN "DNS for $domain failed"; FAILED_CERTS[$domain]=1; continue
    fi
    print -r -- "test_$domain" > /var/www/acme/test_$domain
    typeset http_status=${$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $domain" http://$BRGEN_IP/.well-known/acme-challenge/test_$domain):-000}
    rm -f /var/www/acme/test_$domain
    if [[ $http_status != 200 ]]; then
      log WARN "HTTP test for $domain failed"; FAILED_CERTS[$domain]=1; continue
    fi
    if acme-client -v -f /etc/acme-client.conf "$domain"; then
      generate_tlsa_record "$domain"
    else
      log WARN "Certificate issuance failed for $domain"; FAILED_CERTS[$domain]=1
    fi
  done
  (( $#FAILED_CERTS )) && retry_failed_certs

  install_static usr/local/bin/renew-certs.sh /usr/local/bin/renew-certs.sh
  chmod 755 /usr/local/bin/renew-certs.sh
  install_static usr/local/bin/uptime-check.sh /usr/local/bin/uptime-check.sh
  chmod 755 /usr/local/bin/uptime-check.sh
  install_tracked_crontab || exit 1

  log INFO "Stage 1 complete. ns.brgen.no ($BRGEN_IP) authoritative with DNSSEC."
  log INFO "DS records: doas ruby34 ${REPO_ROOT}/OPENBSD/bin/ds-records — submit each to your registrar (Domeneshop: domain settings → DNSSEC)."
  log INFO "Only for domains the registrar has actually delegated to ns.brgen.no. A DS on a domain we do not serve takes it down."
  log INFO "After submitting DS records, wait 24-48h for propagation, then press Enter to continue."
  log INFO "Verify with: dig DS brgen.no +short"
  read -r
}

# ── Stage 2: services, Rails apps, relayd ─────────────────────────────────────

setup_services() {
  log INFO "Setting up services"
  /usr/sbin/rcctl enable smtpd
  /usr/sbin/rcctl start smtpd || { log ERROR "smtpd failed"; exit 1 }
  sleep 5
  typeset _smtpd_check; _smtpd_check=$(/usr/sbin/rcctl check smtpd)
  [[ $_smtpd_check == *"smtpd(ok)"* ]] || { log ERROR "smtpd not running"; exit 1 }
  /usr/bin/timeout 5 telnet $BRGEN_IP 25 >/dev/null 2>&1 || log WARN "SMTP port 25 not responding"
  /usr/sbin/rcctl enable relayd
  log INFO "Services configured. relayd enabled but not started (awaiting configuration)"
}

setup_mail_client() {
  log INFO "Setting up johann@brgen.no mailbox and mutt"

  # `mutt` and `w3m` each ship several flavours, so the bare names are
  # ambiguous and pkg_add would stop to ask. A trailing `--` pins the
  # flavourless build, which is the one this needs.
  # w3m renders HTML mail, pdftotext (poppler-utils) flattens PDF
  # attachments, chafa draws images as terminal blocks -- see ~johann/.mailcap.
  pkg_add -I mutt-- w3m-- poppler-utils chafa 2>/tmp/pkg_add_mail.log \
    || { log ERROR "pkg_add (mail client) failed. See /tmp/pkg_add_mail.log"; exit 1 }

  getent passwd johann >/dev/null \
    || /usr/sbin/useradd -m -c "Johann (brgen.no mail)" -s /bin/ksh johann \
    || { log ERROR "useradd johann failed"; exit 1 }

  typeset mailhome=/home/johann

  # Maildir++: smtpd delivers into the top level, mutt keeps Sent, Drafts,
  # Trash and Archive as dot-prefixed siblings of it (see .muttrc's +.Sent).
  typeset box
  for box in "" .Sent .Drafts .Trash .Archive; do
    mkdir -p $mailhome/Maildir/$box/cur $mailhome/Maildir/$box/new $mailhome/Maildir/$box/tmp
  done

  # install_static, not install_template: mailimg is a shell script full of
  # ${MAIL_IMG_FMT:-symbols} defaults, which install_template's eval would
  # expand away at install time.
  install_static home/johann/.muttrc  $mailhome/.muttrc
  install_static home/johann/.mailcap $mailhome/.mailcap
  mkdir -p $mailhome/bin
  install_static home/johann/bin/mailimg $mailhome/bin/mailimg
  chmod 755 $mailhome/bin/mailimg

  chown -R johann:johann $mailhome
  chmod 700 $mailhome/Maildir
  chmod 600 $mailhome/.muttrc
}

setup_litestream() {
  # Not in OpenBSD ports and rcctl-disabled on purpose so `rcctl ls failed`
  # stays empty. Install the config for the day a replica exists; do not enable.
  # There is no rc.d/litestream template: the service was retired from boot in
  # e511ccba1 and installing a missing template would abort stage_2.
  log INFO "litestream config only — service stays disabled"
  mkdir -p /var/backups/litestream
  install_template etc/litestream.yml /etc/litestream.yml
}

bootstrap_rails_app() {
  typeset app=$1 port=$2
  typeset app_dir=/home/dev/pub4/RAILS/$app
  typeset secret

  [[ -d $app_dir ]] || { log ERROR "app tree missing: $app_dir"; return 1 }
  log INFO "bootstrapping $app from pub4 tree on :$port"

  su -l dev -c "gem install --user-install rails bundler falcon" >/dev/null 2>&1 || :
  su -l dev -c "cd $app_dir && bundle config set --local deployment true && bundle config set --local without development:test && RAILS_ENV=production bundle install" \
    || { log ERROR "bundle install failed for $app"; return 1 }
  su -l dev -c "cd $app_dir && RAILS_ENV=production bin/rails db:create db:migrate" \
    || log WARN "db:create/migrate non-zero for $app (idempotent skip likely)"
  if [[ -f $app_dir/db/seeds.rb ]]; then
    if [[ ${RUN_PRODUCTION_SEEDS:-0} == 1 ]]; then
      log WARN "$app: RUN_PRODUCTION_SEEDS=1 set; running production db:seed"
      su -l dev -c "cd $app_dir && RAILS_ENV=production bin/rails db:seed"
    else
      log INFO "$app: production db:seed skipped (set RUN_PRODUCTION_SEEDS=1 for explicit one-off seed)"
    fi
  fi

  typeset -a _secret_lines
  _secret_lines=("${(@f)$(su -l dev -c "cd $app_dir && RAILS_ENV=production bundle exec rails secret 2>/dev/null")}")
  secret=${_secret_lines[-1]}
  [[ ${#secret} -ge 64 ]] || { log ERROR "$app: secret capture failed (got ${#secret} chars)"; return 1 }
  [[ -f /etc/${app}.env ]] || print -r -- "SECRET_KEY_BASE=${secret}" > /etc/${app}.env
  # root:<app> 640, not root:wheel: the rc.d script sources /etc/<app>.env at
  # runtime *as the app user* (su -l resets the environment, so the secret cannot
  # be interpolated into daemon_flags without landing in falcon's ps(1) argv —
  # readable by any local account; see rc.d/<app> and TODO.md
  # secrets_in_process_argv). Group-<app> lets only that app (and root) read it,
  # so a foothold in another app user — or dev, which is in wheel — can no longer
  # read this secret at rest.
  chown root:${app} /etc/${app}.env 2>/dev/null || true
  chmod 640 /etc/${app}.env 2>/dev/null || true

  typeset svc=$app
  [[ -f ${CONFIG_ROOT}/etc/rc.d/${svc} ]] || install_template etc/rc.d/rails-app.tmpl /etc/rc.d/${svc}
  chmod 755 /etc/rc.d/${svc}
  /usr/sbin/rcctl enable ${svc}
  /usr/sbin/rcctl restart ${svc} || /usr/sbin/rcctl start ${svc} \
    || { log ERROR "${svc} failed to start"; return 1 }
  sleep 10
  typeset _c; _c=$(/usr/sbin/rcctl check ${svc})
  [[ $_c == *"${svc}(ok)"* ]] || { log ERROR "${svc} not running"; return 1 }
  typeset _http; _http=$(curl -s -o /dev/null -w "%{http_code}" --max-time 30 http://127.0.0.1:${port}/up 2>/dev/null)
  [[ $_http == "200" ]] || log WARN "${svc} /up returned $_http — SECRET_KEY_BASE or DB may need attention"
  log INFO "  ${svc} live on :$port"
}

configure_relayd() {
  log INFO "Writing relayd.conf (TLS+SNI on :443)"

  typeset -A DOMAIN_BACKEND=() BACKEND_PORT=()
  typeset app_entry app dom entry rest sub backend

  for app_entry in $ALL_APPS; do
    app=${app_entry%%:*}; dom=${app_entry##*:}
    DOMAIN_BACKEND[$dom]=$app
    BACKEND_PORT[$app]=${APP_PORTS[$app]:-0}
  done
  DOMAIN_BACKEND[ai.brgen.no]=master
  BACKEND_PORT[master]=${APP_PORTS[master]:-53187}
  for entry in $ALL_DOMAINS; do
    dom=${entry%%:*}
    [[ -n ${DOMAIN_BACKEND[$dom]:-} ]] && continue
    DOMAIN_BACKEND[$dom]=brgen
  done

  for dom in ${(k)DOMAIN_BACKEND}; do
    [[ -f /etc/ssl/${dom}.fullchain.pem ]] || continue
    ln -sf /etc/ssl/${dom}.fullchain.pem /etc/ssl/${dom}.crt
    # Primary domain: key is the real file, not a symlink — nothing to do.
  done
  # Subdomains share the parent cert+key — create both symlinks so relayd
  # tls keypair finds /etc/ssl/${dom}.crt AND /etc/ssl/private/${dom}.key.
  # Skip only domains that have their own fullchain.pem (handled above).
  # Use -sf so existing .crt symlinks don't prevent missing .key from being created.
  for dom in ${(k)DOMAIN_BACKEND}; do
    [[ -f /etc/ssl/${dom}.fullchain.pem ]] && continue
    typeset parent="" try=${dom#*.}
    while [[ -n $try ]]; do
      if [[ -f /etc/ssl/${try}.fullchain.pem ]]; then parent=$try; break; fi
      [[ $try == *.* ]] || break
      try=${try#*.}
    done
    [[ -n $parent ]] || continue
    ln -sf /etc/ssl/${parent}.fullchain.pem /etc/ssl/${dom}.crt
    ln -sf /etc/ssl/private/${parent}.key    /etc/ssl/private/${dom}.key
  done

  install_static etc/relayd.conf /etc/relayd.conf

  relayd -n -f /etc/relayd.conf || { log ERROR "relayd.conf invalid"; exit 1 }
  /usr/sbin/rcctl enable relayd
  /usr/sbin/rcctl restart relayd || /usr/sbin/rcctl start relayd \
    || { log ERROR "relayd failed"; exit 1 }
  sleep 3
  typeset _c; _c=$(/usr/sbin/rcctl check relayd)
  [[ $_c == *"relayd(ok)"* ]] || { log ERROR "relayd not running"; exit 1 }
  log INFO "relayd live — TLS+SNI on :443"
}

configure_dev_ssh() {
  typeset cfg=/home/dev/.ssh/config
  install -d -o dev -g dev -m 700 /home/dev/.ssh
  [[ -f $cfg ]] || install -o dev -g dev -m 600 /dev/null "$cfg"
  typeset existing="$(<$cfg)"
  if [[ $existing != *"Host github.com"* ]]; then
    print -r -- $'\nHost github.com\n  IdentityFile ~/.ssh/id_ed25519_brgen\n  IdentitiesOnly yes' >>"$cfg"
    chown dev:dev "$cfg"
    chmod 600 "$cfg"
    log INFO "dev ssh: github.com block installed"
  fi

  # Ensure the operator dev account uses the modern Zsh environment
  # (packages for zsh + starship + neovim etc. are installed in Stage 1).
  typeset dev_shell=${${(s/:/)$(getent passwd dev)}[-1]}
  if [[ $dev_shell != */zsh ]]; then
    chsh -s /usr/local/bin/zsh dev 2>/dev/null || log WARN "chsh dev to zsh failed (may need manual)"
  fi
}

stage_2() {
  log INFO "Stage 2: services and apps"

  check_dns_propagation

  # `vmstat -s`'s "free memory" line doesn't exist on every OpenBSD release
  # (absent on 7.8) -- read plain `vmstat`'s "fre" column instead, which is
  # always present and (unlike -s) matches what top(1) reports as Free.
  typeset _fre_field; _fre_field=${${(z)$(vmstat | tail -1)}[4]}
  typeset _mem_free_kb
  case $_fre_field in
    *G) _mem_free_kb=$(( ${_fre_field%G} * 1024 * 1024 )) ;;
    *M) _mem_free_kb=$(( ${_fre_field%M} * 1024 )) ;;
    *K) _mem_free_kb=${_fre_field%K} ;;
    *)  _mem_free_kb=$_fre_field ;;
  esac
  # This VPS runs brgen+amber+bsdports+MASTER on ~900MB total RAM -- a few
  # tens of MB free is its normal steady state, not a crisis. This floor
  # catches genuine exhaustion (a leak, a runaway process) without blocking
  # ordinary deploys the way a threshold sized for a bigger box would.
  (( _mem_free_kb < 20000 )) && { log ERROR "Insufficient free memory (${_fre_field} free)"; exit 1 }

  install_static etc/pf.conf /etc/pf.conf
  /sbin/pfctl -nf /etc/pf.conf || { log ERROR "pf.conf invalid"; exit 1 }
  /sbin/pfctl -f /etc/pf.conf  || { log ERROR "pf failed"; exit 1 }

  install_template etc/mail/smtpd.conf /etc/mail/smtpd.conf
  smtpd -n -f /etc/mail/smtpd.conf || { log ERROR "smtpd.conf invalid"; exit 1 }
  [[ ! -f /etc/ssl/private/smtp.key ]] && \
    openssl genpkey -algorithm RSA -out /etc/ssl/private/smtp.key -pkeyopt rsa_keygen_bits:4096
  [[ ! -f /etc/ssl/smtp.crt ]] && \
    openssl req -x509 -new -key /etc/ssl/private/smtp.key -out /etc/ssl/smtp.crt -days 365 -subj "/CN=mail.pub.attorney"
  chmod 640 /etc/ssl/private/smtp.key /etc/ssl/smtp.crt

  setup_mail_client

  setup_services

  typeset -a deploy_order=(amber)
  for app_entry in $ALL_APPS; do
    typeset app=${app_entry[(ws:*:)1]}
    [[ $app != amber ]] && deploy_order+=($app)
  done
  for app in $deploy_order; do
    typeset port=${APP_PORTS[$app]:-}
    [[ -n $port ]] || { log ERROR "missing fixed APP_PORTS entry for $app"; exit 1; }
    bootstrap_rails_app "$app" "$port" || { log ERROR "bootstrap failed: $app"; exit 1 }
  done

  setup_litestream

  for svc_entry in $SERVICES; do
    typeset svc_name=${svc_entry%%:*}
    typeset svc_rest=${svc_entry#*:}
    typeset svc_port=${svc_rest##*:}
    log INFO "Setting up service: $svc_name on port $svc_port"
    chmod 755 /etc/rc.d/$svc_name
    /usr/sbin/rcctl enable $svc_name
    /usr/sbin/rcctl start $svc_name || log WARN "$svc_name start failed (may need manual start)"
  done

  configure_dev_ssh

  log INFO "Deploying MASTER web UI"
  typeset m3dir="/home/dev/pub4/MASTER"
  [[ -d $m3dir ]] || { log ERROR "MASTER not found at $m3dir"; exit 1 }
  cd "$m3dir/web"
  bundle config set --local path vendor/bundle
  bundle config set --local deployment true
  bundle config set --local without 'development test'
  RAILS_ENV=production bundle install --quiet
  # Propshaft must not re-digest public/assets/ (nested assets/assets wedges Falcon boot).
  rm -rf public/assets/assets 2>/dev/null || true
  log INFO "MASTER: building face runtime + precompiling assets"
  RAILS_ENV=production bundle exec rails assets:build_face_runtime assets:build_face_modules_bundle assets:precompile \
    || log WARN "MASTER assets:precompile failed"
  ruby "${REPO_ROOT}/RAILS/gates/runner.rb" master_web_assets 2>/dev/null \
    || ruby "$m3dir/../RAILS/gates/runner.rb" master_web_assets 2>/dev/null \
    || log WARN "MASTER master_web_assets_gate skipped"
  typeset master_secret
  typeset -a _master_secret_lines
  _master_secret_lines=("${(@f)$(RAILS_ENV=production bundle exec rails secret 2>/dev/null)}")
  master_secret=${_master_secret_lines[-1]}
  [[ ${#master_secret} -ge 64 ]] || { log ERROR "master: secret capture failed (got ${#master_secret} chars)"; exit 1 }
  [[ -f ${CONFIG_ROOT}/etc/rc.d/master ]] || { log ERROR "missing OPENBSD/etc/rc.d/master"; exit 1 }
  cp "${CONFIG_ROOT}/etc/rc.d/master" /etc/rc.d/master
  chmod 555 /etc/rc.d/master
  [[ -f $m3dir/data/soul.yml ]] && chmod 0444 "$m3dir/data/soul.yml"
  [[ -f $m3dir/data/checksums.yml ]] && chmod 0444 "$m3dir/data/checksums.yml"
  rcctl enable master
  rcctl start master
  log INFO "MASTER web UI running on :53187"

  configure_relayd

  log INFO "Deploy complete. Test: curl https://brgen.no, rcctl check master"
}

# ── Entry point ───────────────────────────────────────────────────────────────

deploy_live() {
  sync_openbsd_apply "${CONFIG_ROOT}"
}

main() {
  if [[ ${1:-} = --help ]]; then
    print -r -- "OpenBSD vm23 deploy (OPERATOR.sh). Config trees: etc/ usr/ var/ → /.
Usage:
  cd ~/pub4 && doas zsh OPENBSD/OPERATOR.sh

Default: install configs, validate pf/relayd, restart services.

Rare:
  doas zsh OPERATOR.sh --first-install
  doas zsh OPERATOR.sh --stage-1        # requires I_UNDERSTAND_DNS_WIPE=1
  doas zsh OPERATOR.sh --stage-2

--sync-configs is an alias for the default."
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
      ruby34 "${SCRIPT_DIR}/verify_openbsd_idempotency.rb" || exit 1
      ruby34 "${SCRIPT_DIR}/verify_deploy_identity.rb" || exit 1
      stage_1
      stage_2
      ;;
    --stage-1|--stage1)
      [[ ${I_UNDERSTAND_DNS_WIPE:-0} == 1 ]] || {
        log ERROR "stage_1 rewrites DNS material; rerun with I_UNDERSTAND_DNS_WIPE=1 if this is intentional"
        exit 1
      }
      ruby34 "${SCRIPT_DIR}/verify_openbsd_idempotency.rb" || exit 1
      ruby34 "${SCRIPT_DIR}/verify_deploy_identity.rb" || exit 1
      stage_1
      ;;
    --stage-2|--stage2)
      ruby34 "${SCRIPT_DIR}/verify_openbsd_idempotency.rb" || exit 1
      ruby34 "${SCRIPT_DIR}/verify_deploy_identity.rb" || exit 1
      stage_2
      ;;
    "")
      deploy_live
      ;;
    *)
      log ERROR "unknown flag: $1 (try --help)"
      exit 1
      ;;
  esac
}

main "$@"
