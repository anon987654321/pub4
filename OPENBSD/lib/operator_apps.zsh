#!/usr/bin/env zsh
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
  pkg_add -I mutt-- w3m-- poppler-utils chafa 2>/var/log/pkg_add_mail.log \
    || { log ERROR "pkg_add (mail client) failed. See /var/log/pkg_add_mail.log"; exit 1 }

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
  su -l dev -c "cd $app_dir && RAILS_ENV=production bin/rails db:prepare" \
    || log WARN "db:prepare non-zero for $app (idempotent skip likely)"
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
  # An app with no rc.d script of its own gets brgen's with the name and port
  # swapped, so a new service starts from the one running in production: set -a
  # around the env file, the PATH for curl, rc_pre and the relayd kick. A
  # separate template drifted from it and would have installed none of those.
  if [[ ! -f ${CONFIG_ROOT}/etc/rc.d/${svc} ]]; then
    typeset _rc; _rc=$(<"${CONFIG_ROOT}/etc/rc.d/brgen")
    _rc=${_rc//brgen/${app}}
    print -r -- "${_rc//38182/${port}}" > /etc/rc.d/${svc}
  fi
  # 555, the mode brgen, amber and bsdports already carry on vm23 — see
  # install_root_configs for why this repo's rc.d scripts are read-only and
  # OpenBSD's own are not. 755 here would flatten that on the next app install.
  chmod 555 /etc/rc.d/${svc}
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

