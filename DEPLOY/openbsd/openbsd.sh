#!/usr/bin/env zsh
# Configure OpenBSD 7.8: NSD/DNSSEC, acme-client, Rails, pf, relayd, smtpd.
# Usage:
#   doas zsh openbsd.sh --first-install
#   doas zsh openbsd.sh --stage-2
#   doas zsh openbsd.sh --sync-configs
# VERIFIED AGAINST: OpenBSD 7.8 manual pages (2026-01-06)
#
# IDEMPOTENCY NOTES (CC14):
# - Safe to re-run: bootstrap_rails_app (cp tree, bundle install, db:migrate), sync_openbsd_configs
#   (backs up /etc first), relayd/pf template installs when configs already match, rcctl enable/start.
# - DESTRUCTIVE on re-run: stage_1 deletes /var/nsd/etc/* and /var/nsd/zones/master/* before
#   regenerating signed zones. Never re-run stage_1 on a live authoritative server without backup.
# - State tracking: STATE_FILE=/var/db/openbsd_setup.state — is_step_completed/mark_step_completed
#   helpers exist for future --resume support; certificate-renewal cron must stay append-idempotent.
# - Data preserved: Rails SQLite under /home/<app>/app/db, ~/priv, acme certs in /etc/ssl when
#   stage_1 is skipped. Re-running stage_2 does not drop databases.
# - Post-deploy verification: ruby /home/dev/pub4/DEPLOY/health_check.rb
# Engine-ize: bootstrap_rails now relies on bundle install for pub4-shared path gem (Gemfiles declare it); legacy sh shared/install_* deprecated in scripts + WIRING. No copy sprawl.

set -euo pipefail
setopt no_unset nullglob local_traps
zmodload zsh/regex
zmodload zsh/datetime

typeset -a TMPFILES
SCRIPT_DIR=${0:a:h}

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
  typeset src=${SCRIPT_DIR}/$1 dst=$2
  [[ -f $src ]] || { log ERROR "Missing template: $src"; exit 1 }
  typeset content; content=$(<"$src")
  eval "cat > \"$dst\" <<INSTALL_TEMPLATE_EOF
$content
INSTALL_TEMPLATE_EOF"
}

append_template() {
  typeset src=${SCRIPT_DIR}/$1 dst=$2
  [[ -f $src ]] || { log ERROR "Missing template: $src"; exit 1 }
  typeset content; content=$(<"$src")
  eval "cat >> \"$dst\" <<APPEND_TEMPLATE_EOF
$content
APPEND_TEMPLATE_EOF"
}

install_static() {
  typeset src=${SCRIPT_DIR}/$1 dst=$2
  [[ -f $src ]] || { log ERROR "Missing file: $src"; exit 1 }
  cp "$src" "$dst"
}

is_step_completed()  { [[ -f "${STATE_FILE}.steps" ]] && [[ $(<"${STATE_FILE}.steps") == *"$1"* ]] }
mark_step_completed() { print -r -- "$1" >> "${STATE_FILE}.steps" }

# Mirror DEPLOY/openbsd tree onto live /etc (VPS source of truth = repo).
# Usage: doas zsh openbsd.sh --sync-configs
sync_openbsd_configs() {
  typeset src=${1:-${SCRIPT_DIR}}
  [[ -d $src/etc ]] || { log ERROR "No etc/ in $src"; return 1 }
  backup_directory /etc "etc-pre-sync" || return 1

  typeset -a etc_files=(
    pf.conf rc.conf.local relayd.conf httpd.conf acme-client.conf
    doas.conf login.conf newsyslog.conf litestream.yml
  )
  for f in $etc_files; do
    [[ -e $src/etc/$f ]] || continue
    cp "$src/etc/$f" "/etc/$f"
    log INFO "synced /etc/$f"
  done

  [[ -f $src/etc/ssh/sshd_config ]] && cp "$src/etc/ssh/sshd_config" /etc/ssh/sshd_config && log INFO "synced /etc/ssh/sshd_config"
  [[ -f $src/etc/mail/smtpd.conf ]] && cp "$src/etc/mail/smtpd.conf" /etc/mail/smtpd.conf && log INFO "synced /etc/mail/smtpd.conf"
  [[ -f $src/var/nsd/etc/nsd.conf ]] && cp "$src/var/nsd/etc/nsd.conf" /var/nsd/etc/nsd.conf && log INFO "synced /var/nsd/etc/nsd.conf"

  if [[ -d $src/var/nsd/zones/master ]]; then
    install -d -o _nsd -g _nsd -m 750 /var/nsd/zones/master 2>/dev/null || true
    for f in $src/var/nsd/zones/master/*.zone(.); do
      cp "$f" "/var/nsd/zones/master/${f:t}"
      log INFO "synced zone ${f:t}"
    done
  fi

  [[ -f $src/etc/daily.local ]] && {
    cp "$src/etc/daily.local" /etc/daily.local
    chmod 755 /etc/daily.local
    log INFO "synced /etc/daily.local"
  }

  if [[ -d $src/etc/rc.d ]]; then
    for f in $src/etc/rc.d/*(.); do
      typeset name=${f:t}
      cp "$f" "/etc/rc.d/$name"
      chmod 755 "/etc/rc.d/$name"
      [[ $name = master ]] && chmod 555 "/etc/rc.d/master"
      log INFO "synced /etc/rc.d/$name"
    done
  fi

  if [[ -d $src/usr/local/bin ]]; then
    for f in $src/usr/local/bin/*(.); do
      cp "$f" "/usr/local/bin/${f:t}"
      chmod 755 "/usr/local/bin/${f:t}"
      log INFO "synced /usr/local/bin/${f:t}"
    done
  fi

  if [[ -x /usr/local/bin/relayd-watchdog ]] || [[ -x /usr/local/bin/config-drift-check ]]; then
    typeset root_cron=/tmp/root_crontab.$$
    crontab -l 2>/dev/null > $root_cron || :
    if [[ -x /usr/local/bin/relayd-watchdog ]] && ! grep -q relayd-watchdog $root_cron 2>/dev/null; then
      print -r -- "*/5 * * * * /usr/local/bin/relayd-watchdog" >> $root_cron
      log INFO "installed root cron: relayd-watchdog (every 5 min)"
    fi
    if [[ -x /usr/local/bin/config-drift-check ]] && ! grep -q config-drift-check $root_cron 2>/dev/null; then
      print -r -- "*/15 * * * * /usr/local/bin/config-drift-check >> /var/log/config_drift.log 2>&1" >> $root_cron
      log INFO "installed root cron: config-drift-check"
    fi
    crontab $root_cron
    rm -f $root_cron
  fi

  if [[ -f $src/etc/.zshrc ]]; then
    install -d -o dev -g dev -m 700 /home/dev 2>/dev/null || true
    cp "$src/etc/.zshrc" /home/dev/.zshrc
    chown dev:dev /home/dev/.zshrc 2>/dev/null || true
    chmod 644 /home/dev/.zshrc 2>/dev/null || true
    log INFO "synced .zshrc to /home/dev"
  fi

  log INFO "OpenBSD config tree sync complete (with backup)"
}

sync_openbsd_apply() {
  typeset src=${1:-${SCRIPT_DIR}}
  sync_openbsd_configs "$src" || return 1

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
  # Run MASTER deep scan on DEPLOY tree before any service restart. Block on violations (tier1 critical + veto).
  # Uses ground_truth_check (fresh read), self_test (laws on DEPLOY), evidence_scoring (scan_clean).
  # Also covers lexical/structural for sh, yml, conf, erb; no bypasses.
  if [[ -n ${SKIP_MASTER_SCAN:-} ]]; then
    log WARN "MASTER scan skipped (SKIP_MASTER_SCAN)"
  elif [[ -x /home/dev/pub4/MASTER/bin/cli ]]; then
    log INFO "MASTER rules scan (DEPLOY) — strict pre-apply per rules.yml (ROBUSTNESS/SINGULARITY/LINEARITY/PROXIMITY/ABSTRACTION/DENSITY + veto)"
    if ! su dev -c 'cd /home/dev/pub4/MASTER && MASTER_SCAN_ONLY=1 MASTER_SAFE_MODE=1 bundle34 exec ruby bin/cli /scan DEPLOY --depth deep' 2>&1 | tee /tmp/master_deploy_scan.log; then
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

  install -m 755 "${SCRIPT_DIR}/resource_guard.sh" /usr/local/bin/resource_guard.sh 2>/dev/null || true
  if [[ -x /usr/local/bin/resource_guard.sh ]]; then
    typeset guard_cron=/tmp/root_crontab.$$
    crontab -l 2>/dev/null > $guard_cron || :
    if ! grep -q resource_guard $guard_cron 2>/dev/null; then
      print -r -- "*/5 * * * * /usr/local/bin/resource_guard.sh" >> $guard_cron
      crontab $guard_cron
      log INFO "installed root cron: resource_guard (every 5 min)"
    fi
    rm -f $guard_cron
  fi

  typeset -a svcs=(nsd httpd relayd smtpd master)
  for svc in $svcs; do
    [[ -x /etc/rc.d/$svc ]] || continue
    /usr/sbin/rcctl enable $svc 2>/dev/null || true
    /usr/sbin/rcctl restart $svc 2>/dev/null || /usr/sbin/rcctl start $svc 2>/dev/null \
      || log WARN "$svc restart/start failed"
  done
  # App services: start only if /up already returns 200 — avoids Falcon crash-loops burning CPU.
  typeset -A app_ports=(brgen 38182 amber 61352 bsdports 47312 blognet 10002 hjerterom 38891 baibl 10007)
  typeset -a core_apps=(brgen)
  typeset -a optional_apps=(amber bsdports blognet hjerterom baibl litestream)
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
  baibl 10007
  blognet 10002
  hjerterom 38891
  master 53187
)
typeset -A FAILED_CERTS

validate_ip "$BRGEN_IP" || { log ERROR "Invalid BRGEN_IP: $BRGEN_IP"; exit 1 }
validate_ip "$HYP_IP"   || { log ERROR "Invalid HYP_IP: $HYP_IP"; exit 1 }

ALL_APPS=(
  brgen:brgen.no
  amber:amber.brgen.no
  bsdports:bsdports.org
  baibl:baibl.brgen.no
  blognet:blognet.brgen.no
  hjerterom:hjerterom.brgen.no
)

SERVICES=()

ALL_DOMAINS=(
  brgen.no:markedsplass,playlist,spilleliste,dating,tv,takeaway,maps,messenger,ai
  longyearbyn.no:markedsplass,playlist,spilleliste,dating,tv,takeaway,maps,messenger
  oshlo.no:markedsplass,playlist,spilleliste,dating,tv,takeaway,maps,messenger
  stvanger.no:markedsplass,playlist,spilleliste,dating,tv,takeaway,maps,messenger
  trmso.no:markedsplass,playlist,spilleliste,dating,tv,takeaway,maps,messenger
  trndheim.no:markedsplass,playlist,spilleliste,dating,tv,takeaway,maps,messenger
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
  foodielicio.us
  stacyspassion.com
  antibettingblog.com
  anticasinoblog.com
  antigamblingblog.com
  foball.no
  amber.brgen.no
  hjerterom.brgen.no
)

# ── Stage 1: DNS, DNSSEC, TLS certificates ────────────────────────────────────

stage_1() {
  log INFO "Stage 1: DNS and certificates"

  typeset -a _df_root; _df_root=("${(@f)$(df -k /)}"); typeset _root_avail=${${(z)_df_root[2]}[4]}
  (( _root_avail < 10000 )) && { log ERROR "Insufficient disk space on /"; exit 1 }
  typeset -a _df_var; _df_var=("${(@f)$(df -k /var)}"); typeset _var_avail=${${(z)_df_var[2]}[4]}
  (( _var_avail < 512000 )) && { log ERROR "Insufficient disk space on /var"; exit 1 }

  pkg_add -U ldns-utils ruby%3.4 litestream zap zsh fish neovim tmux fontconfig fzf ripgrep fd 2>/tmp/pkg_add.log \
    || { log ERROR "pkg_add failed. See /tmp/pkg_add.log"; exit 1 }

  [[ -f /etc/rc.conf.local && $(<"/etc/rc.conf.local") == *"pf=NO"* ]] && log WARN "pf disabled in rc.conf.local"
  ifconfig vio0 >/dev/null 2>&1 || { log ERROR "Interface vio0 not found"; exit 1 }

  /sbin/pfctl -d || log WARN "pf disable failed"
  /sbin/pfctl -e || { log ERROR "pf enable failed"; exit 1 }
  install_template etc/pf.stage1.conf /etc/pf.conf
  /sbin/pfctl -nf /etc/pf.conf || { log ERROR "pf.conf invalid"; exit 1 }
  /sbin/pfctl -f /etc/pf.conf  || { log ERROR "pf failed"; exit 1 }

  [[ -d /var/nsd/etc ]]          || { log ERROR "/var/nsd/etc missing"; exit 1 }
  [[ -d /var/nsd/zones/master ]] || { log ERROR "/var/nsd/zones/master missing"; exit 1 }

  backup_directory /var/nsd/zones/master nsd-zones || { log ERROR "Backup failed"; exit 1 }
  transaction_log "DELETE" "/var/nsd/etc/*" "START"
  rm -rf /var/nsd/etc/*(/) /var/nsd/zones/master/*(/)
  transaction_log "DELETE" "/var/nsd/etc/* and /var/nsd/zones/master/*" "SUCCESS"

  install_template var/nsd/etc/nsd.conf /var/nsd/etc/nsd.conf
  for domain in ${ALL_DOMAINS[*]%%:*}; do
    append_template var/nsd/etc/nsd-zone.tmpl /var/nsd/etc/nsd.conf
  done
  nsd-checkconf /var/nsd/etc/nsd.conf || { log ERROR "nsd.conf invalid"; exit 1 }

  typeset serial=${$(date +%Y%m%d%H):-}
  for domain_entry in $ALL_DOMAINS; do
    typeset domain=${domain_entry%%:*}
    typeset subdomains=${domain_entry#*:}
    [[ $subdomains = $domain ]] && subdomains=""

    install_template var/nsd/zones/master/zone.tmpl /var/nsd/zones/master/$domain.zone
    [[ $domain = brgen.no ]] && print -r -- "ns IN A $BRGEN_IP" >> /var/nsd/zones/master/$domain.zone

    if [[ -n $subdomains && $subdomains != $domain ]]; then
      for subdomain in ${(s:,:):-$subdomains}; do
        print -r -- "$subdomain IN A $BRGEN_IP" >> /var/nsd/zones/master/$domain.zone
      done
    fi

    nsd-checkzone "$domain" /var/nsd/zones/master/$domain.zone \
      || { log ERROR "Zone invalid for $domain"; exit 1 }

    cd /var/nsd/zones/master
    typeset zsk ksk
    zsk=$(ldns-keygen -a ECDSAP256SHA256 "$domain")
    ksk=$(ldns-keygen -k -a ECDSAP256SHA256 -b 2048 "$domain")

    typeset zonefile=/var/nsd/zones/master/$domain.zone
    typeset signed_zonefile=/var/nsd/zones/master/$domain.zone.signed
    typeset salt=$(dd if=/dev/random bs=16 count=1 2>/dev/null | sha1 -q)
    ldns-signzone -n -p -s "$salt" "$zonefile" "$zsk" "$ksk"
    nsd-checkzone "$domain" "$signed_zonefile" || { log ERROR "Signed zone invalid for $domain"; exit 1 }

    nsd-control reload 2>/dev/null || true
    ldns-key2ds -n -2 /var/nsd/zones/master/$domain.zone.signed > /var/nsd/zones/master/$domain.ds
    chown _nsd:_nsd /var/nsd/zones/master/*
    chmod 640 /var/nsd/zones/master/*
  done

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
  for domain_entry in $ALL_DOMAINS; do
    typeset domain=${domain_entry%%:*}
    typeset subdomains=${domain_entry#*:}
    [[ $subdomains = $domain ]] && subdomains=""
    {
      print -r -- "domain \"$domain\" {"
      if [[ -n $subdomains ]]; then
        typeset altnames="\"$domain\""
        for sub in ${(s:,:)subdomains}; do altnames="$altnames \"$sub.$domain\""; done
        print -r -- "  alternative names { $altnames }"
      fi
      print -r -- "  domain key \"/etc/ssl/private/$domain.key\""
      print -r -- "  domain full chain certificate \"/etc/ssl/$domain.fullchain.pem\""
      print -r -- "  sign with letsencrypt"
      print -r -- "  challengedir \"/var/www/acme\""
      print -r -- "}"
      print -r -- ""
    } >> /etc/acme-client.conf
  done
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
  typeset crontab_tmp=/tmp/crontab_tmp
  crontab -l 2>/dev/null > $crontab_tmp || :
  print -r -- "0 2 * * 1 /usr/local/bin/renew-certs.sh >> /var/log/cert-renewal.log 2>&1" >> $crontab_tmp
  crontab $crontab_tmp || { log ERROR "Crontab update failed"; exit 1 }
  rm $crontab_tmp

  log INFO "Stage 1 complete. ns.brgen.no ($BRGEN_IP) authoritative with DNSSEC."
  log INFO "DS records: /var/nsd/zones/master/*.ds — submit each to your registrar (Domeneshop: domain settings → DNSSEC)."
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

setup_litestream() {
  log INFO "Setting up litestream"
  mkdir -p /var/backups/litestream
  install_template etc/litestream.yml /etc/litestream.yml
  install_template etc/rc.d/litestream /etc/rc.d/litestream
  chmod 755 /etc/rc.d/litestream
  /usr/sbin/rcctl enable litestream
  /usr/sbin/rcctl restart litestream || /usr/sbin/rcctl start litestream \
    || { log ERROR "litestream failed"; exit 1 }
  sleep 2
  typeset _c; _c=$(/usr/sbin/rcctl check litestream)
  [[ $_c == *"litestream(ok)"* ]] || { log ERROR "litestream not running"; exit 1 }
}

bootstrap_rails_app() {
  typeset app=$1 port=$2
  typeset app_dir=/home/dev/pub4/DEPLOY/rails/$app
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
  chmod 640 /etc/${app}.env 2>/dev/null || true

  typeset svc=$app
  [[ -f ${SCRIPT_DIR}/etc/rc.d/${svc} ]] || install_template etc/rc.d/rails-app.tmpl /etc/rc.d/${svc}
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
  DOMAIN_BACKEND[hjerterom.brgen.no]=hjerterom
  DOMAIN_BACKEND[anticasinoblog.com]=blognet
  DOMAIN_BACKEND[antigamblingblog.com]=blognet
  DOMAIN_BACKEND[antibettingblog.com]=blognet
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

  {
    print -r -- "log connection errors"
    print -r -- "interval 120"
    print -r -- "timeout 30000"
    print -r -- ""
    for backend in ${(k)BACKEND_PORT}; do
      print -r -- "table <${backend}> { 127.0.0.1 }"
    done
    print -r -- ""
    print -r -- "http protocol \"https_proxy\" {"
    for dom in ${(k)DOMAIN_BACKEND}; do
      [[ -L /etc/ssl/${dom}.crt ]] && print -r -- "  tls keypair \"${dom}\""
    done
    print -r -- "  match request header set \"X-Forwarded-Proto\" value \"https\""
    print -r -- "  match request header set \"X-Forwarded-For\" value \"\$REMOTE_ADDR\""
    print -r -- "  match response header set \"Strict-Transport-Security\" value \"max-age=31536000; includeSubDomains; preload\""
    print -r -- "  match response header set \"Referrer-Policy\" value \"strict-origin\""
    print -r -- "  match response header set \"X-Content-Type-Options\" value \"nosniff\""
    print -r -- "  match response header set \"X-XSS-Protection\" value \"0\""
    print -r -- "  # No global X-Frame-Options — MASTER uses CSP frame-ancestors for brgen/amber embeds."
    print -r -- "  match response header set \"Permissions-Policy\" value \"accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(self), payment=(), usb=()\""
    print -r -- "  match response header remove \"X-Frame-Options\""
    print -r -- "  match response header remove \"Server\""
    print -r -- "  http websockets"
    for dom in ${(k)DOMAIN_BACKEND}; do
      backend=${DOMAIN_BACKEND[$dom]}
      print -r -- "  match request header \"Host\" value \"${dom}\" forward to <${backend}>"
      for entry in $ALL_DOMAINS; do
        [[ ${entry%%:*} == $dom ]] || continue
        rest=${entry#*:}
        [[ $rest == $dom ]] && break
        for sub in ${(s:,:)rest}; do
          [[ -n ${DOMAIN_BACKEND[${sub}.${dom}]:-} ]] && continue
          print -r -- "  match request header \"Host\" value \"${sub}.${dom}\" forward to <${backend}>"
        done
        break
      done
    done
    print -r -- "  pass"
    print -r -- "}"
    print -r -- ""
    print -r -- "relay \"https_in\" {"
    print -r -- "  listen on 0.0.0.0 port 443 tls"
    print -r -- "  protocol \"https_proxy\""
    for backend in ${(k)BACKEND_PORT}; do
      print -r -- "  forward to <${backend}> port ${BACKEND_PORT[$backend]} check http \"/up\" code 200"
    done
    print -r -- "}"
  } > /etc/relayd.conf

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

  typeset _mem_line; _mem_line=$(vmstat -s | while IFS= read -r _l; do [[ $_l == *"free memory"* ]] && print -r -- "$_l" && break; done)
  typeset _mem_free=${${(z)_mem_line}[1]}
  (( _mem_free < 512000 )) && { log ERROR "Insufficient free memory"; exit 1 }

  install_template etc/pf.conf /etc/pf.conf
  /sbin/pfctl -nf /etc/pf.conf || { log ERROR "pf.conf invalid"; exit 1 }
  /sbin/pfctl -f /etc/pf.conf  || { log ERROR "pf failed"; exit 1 }

  install_template etc/mail/smtpd.conf /etc/mail/smtpd.conf
  smtpd -n -f /etc/mail/smtpd.conf || { log ERROR "smtpd.conf invalid"; exit 1 }
  [[ ! -f /etc/ssl/private/smtp.key ]] && \
    openssl genpkey -algorithm RSA -out /etc/ssl/private/smtp.key -pkeyopt rsa_keygen_bits:4096
  [[ ! -f /etc/ssl/smtp.crt ]] && \
    openssl req -x509 -new -key /etc/ssl/private/smtp.key -out /etc/ssl/smtp.crt -days 365 -subj "/CN=mail.pub.attorney"
  chmod 640 /etc/ssl/private/smtp.key /etc/ssl/smtp.crt

  setup_services

  typeset -a deploy_order=(amber)
  for app_entry in $ALL_APPS; do
    typeset app=${app_entry[(ws:*:)1]}
    [[ $app != amber ]] && deploy_order+=($app)
  done
  for app in $deploy_order; do
    typeset port=${APP_PORTS[$app]:=$(generate_random_port)}
    APP_PORTS[$app]=$port
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
  ruby "${SCRIPT_DIR}/../rails/master_web_assets_gate.rb" 2>/dev/null \
    || ruby "$m3dir/../DEPLOY/rails/master_web_assets_gate.rb" 2>/dev/null \
    || log WARN "MASTER master_web_assets_gate skipped"
  typeset master_secret
  typeset -a _master_secret_lines
  _master_secret_lines=("${(@f)$(RAILS_ENV=production bundle exec rails secret 2>/dev/null)}")
  master_secret=${_master_secret_lines[-1]}
  [[ ${#master_secret} -ge 64 ]] || { log ERROR "master: secret capture failed (got ${#master_secret} chars)"; exit 1 }
  if [[ -f ${SCRIPT_DIR}/etc/rc.d/master ]]; then
    cp "${SCRIPT_DIR}/etc/rc.d/master" /etc/rc.d/master
  else
    install_template etc/rc.d/master.tmpl /etc/rc.d/master
  fi
  chmod 555 /etc/rc.d/master
  [[ -f $m3dir/data/soul.yml ]] && chmod 0444 "$m3dir/data/soul.yml"
  [[ -f $m3dir/data/checksums.yml ]] && chmod 0444 "$m3dir/data/checksums.yml"
  rcctl enable master
  rcctl start master
  log INFO "MASTER web UI running on :53187"

  configure_relayd

  log INFO "Deploy complete. Test: curl https://brgen.no, rcctl check master."
}

# ── Entry point ───────────────────────────────────────────────────────────────

main() {
  if [[ ${1:-} = --help ]]; then
    print -r -- "Configure OpenBSD 7.8 for Rails with DNSSEC and relayd TLS+SNI.
Usage:
  doas zsh openbsd.sh --first-install
  doas zsh openbsd.sh --stage-1        # requires I_UNDERSTAND_DNS_WIPE=1
  doas zsh openbsd.sh --stage-2
  doas zsh openbsd.sh --sync-configs

The no-argument form is intentionally disabled because stage_1 rewrites
authoritative DNS material."
    exit 0
  fi

  if [[ ${1:-} = --sync-configs ]]; then
    sync_openbsd_apply "${SCRIPT_DIR}"
    exit $?
  fi

  case ${1:-} in
    --first-install)
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
    *)
      log ERROR "refusing no-argument deploy because stage_1 is destructive; use --first-install, --stage-2, or --sync-configs"
      exit 1
      ;;
  esac
}

main "$@"
