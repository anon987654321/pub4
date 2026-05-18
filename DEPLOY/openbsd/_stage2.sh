#!/usr/bin/env zsh
# Stage 2: services, Rails apps, relayd.

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

bootstrap_rails_app() {
  typeset app=$1 port=$2
  typeset src=/home/dev/pub4/DEPLOY/rails/$app/app
  typeset app_dir=/home/$app/app
  typeset bundle_home=/home/$app/.bundle
  typeset secret

  [[ -d $src ]] || { log ERROR "source tree missing: $src"; return 1 }
  log INFO "bootstrapping $app -> $app_dir on :$port"

  id "$app" >/dev/null 2>&1 || useradd -m -L daemon -s /bin/ksh "$app"
  mkdir -p "$app_dir"
  cp -R "${src}/." "${app_dir}/"
  chown -R "${app}:${app}" "/home/$app"

  if [[ ! -d $bundle_home/gems && $app != amber && -d /home/amber/.bundle/gems ]]; then
    log INFO "  seeding gems from amber donor"
    mkdir -p "$bundle_home"
    cp -R /home/amber/.bundle/gems "$bundle_home/"
    chown -R "${app}:${app}" "$bundle_home"
    mkdir -p "$app_dir/.bundle"
    print -r -- "---" > "$app_dir/.bundle/config"
    print -r -- "BUNDLE_PATH: \"${bundle_home}/gems\"" >> "$app_dir/.bundle/config"
    chown "${app}:${app}" "$app_dir/.bundle/config"
  fi

  su -l "$app" -c "gem install --user-install rails bundler falcon" >/dev/null 2>&1 || :
  su -l "$app" -c "cd $app_dir && bundle config set --local deployment true && bundle config set --local without development:test && RAILS_ENV=production bundle install" \
    || { log ERROR "bundle install failed for $app"; return 1 }
  su -l "$app" -c "cd $app_dir && RAILS_ENV=production bin/rails db:create db:migrate" \
    || log WARN "db:create/migrate non-zero for $app (idempotent skip likely)"
  [[ -f $app_dir/db/seeds.rb ]] && \
    su -l "$app" -c "cd $app_dir && RAILS_ENV=production bin/rails db:seed" || :

  secret=$(su -l "$app" -c "cd $app_dir && RAILS_ENV=production bundle exec rails secret 2>/dev/null" | tail -1)
  [[ ${#secret} -ge 64 ]] || { log ERROR "$app: secret capture failed (got ${#secret} chars)"; return 1 }
  install_template etc/rc.d/rails-app.tmpl /etc/rc.d/$app
  chmod 755 /etc/rc.d/$app
  /usr/sbin/rcctl enable $app
  /usr/sbin/rcctl restart $app || /usr/sbin/rcctl start $app \
    || { log ERROR "$app failed to start"; return 1 }
  sleep 5
  typeset _c; _c=$(/usr/sbin/rcctl check $app)
  [[ $_c == *"${app}(ok)"* ]] || { log ERROR "$app not running"; return 1 }
  typeset _http; _http=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 http://127.0.0.1:${port}/up 2>/dev/null)
  [[ $_http == "200" ]] || log WARN "$app /up returned $_http — SECRET_KEY_BASE or DB may need attention"
  log INFO "  $app live on :$port"
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
  BACKEND_PORT[master]=53187
  for entry in $ALL_DOMAINS; do
    dom=${entry%%:*}
    [[ -n ${DOMAIN_BACKEND[$dom]:-} ]] && continue
    DOMAIN_BACKEND[$dom]=brgen
  done

  for dom in ${(k)DOMAIN_BACKEND}; do
    [[ -f /etc/ssl/${dom}.fullchain.pem ]] || continue
    ln -sf /etc/ssl/${dom}.fullchain.pem /etc/ssl/${dom}.crt
  done

  {
    print -r -- "log connection"
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
    print -r -- "  match request header set \"X-Forwarded-For\"   value \"\$REMOTE_ADDR\""
    print -r -- "  match response header set \"Strict-Transport-Security\" value \"max-age=31536000; includeSubDomains; preload\""
    print -r -- "  match response header set \"Content-Security-Policy\" value \"upgrade-insecure-requests; default-src https: 'self'\""
    print -r -- "  match response header set \"Referrer-Policy\" value \"strict-origin\""
    print -r -- "  match response header set \"X-Content-Type-Options\" value \"nosniff\""
    print -r -- "  match response header set \"X-Frame-Options\" value \"SAMEORIGIN\""
    print -r -- "  match response header set \"X-XSS-Protection\" value \"1; mode=block\""
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
      print -r -- "  forward to <${backend}> port ${BACKEND_PORT[$backend]} check tcp"
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

stage_2() {
  log INFO "Starting Stage 2: Services and Apps"

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

  for svc_entry in $SERVICES; do
    typeset svc_name=${svc_entry%%:*}
    typeset svc_rest=${svc_entry#*:}
    typeset svc_fqdn=${svc_rest%%:*}
    typeset svc_port=${svc_rest##*:}
    log INFO "Setting up service: $svc_name on port $svc_port"
    log INFO "Service $svc_name handled by master rc.d"
    chmod 755 /etc/rc.d/$svc_name
    /usr/sbin/rcctl enable $svc_name
    /usr/sbin/rcctl start $svc_name || log WARN "$svc_name start failed (may need manual start)"
  done

  if ! is_step_completed "master_deployed"; then
    log INFO "Deploying MASTER web UI"
    typeset m3dir="/home/dev/pub4/MASTER"
    [[ -d $m3dir ]] || { log ERROR "MASTER not found at $m3dir"; exit 1 }
    cd "$m3dir/web"
    bundle config set --local path vendor/bundle
    bundle install --quiet
    typeset master_secret
    master_secret=$(RAILS_ENV=production bundle exec rails secret 2>/dev/null | tail -1)
    [[ ${#master_secret} -ge 64 ]] || { log ERROR "master: secret capture failed (got ${#master_secret} chars)"; exit 1 }
    typeset env_line=""
    while IFS= read -r _line; do
      [[ $_line == export* ]] || continue
      typeset _kv=${_line#export }
      env_line="$env_line ${_kv%%=*}=${_kv#*=}"
    done < /home/dev/.zshrc
    install_template etc/rc.d/master.tmpl /etc/rc.d/master
    chmod 555 /etc/rc.d/master
    rcctl enable master
    rcctl start master
    mark_step_completed "master_deployed"
    log INFO "MASTER web UI running on :53187 (relayd :3000 -> :53187)"
  fi

  configure_relayd

  print -r -- stage_2_complete > $STATE_FILE
  log INFO "Stage 2 complete. Test: curl https://brgen.no, rcctl check master."
  exit 0
}
