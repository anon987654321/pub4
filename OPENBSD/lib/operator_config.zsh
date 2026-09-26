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

