#!/usr/bin/env zsh
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
    chmod 555 /etc/rc.d/$svc_name
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

