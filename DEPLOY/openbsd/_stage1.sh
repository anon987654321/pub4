#!/usr/bin/env zsh
# Stage 1: DNS, DNSSEC, TLS certificates.

stage_1() {
  log INFO "Starting Stage 1: DNS and Certificates"

  typeset -a _df_root; _df_root=("${(@f)$(df -k /)}"); typeset _root_avail=${${(z)_df_root[2]}[4]}
  (( _root_avail < 10000 )) && { log ERROR "Insufficient disk space on /"; exit 1 }
  typeset -a _df_var; _df_var=("${(@f)$(df -k /var)}"); typeset _var_avail=${${(z)_df_var[2]}[4]}
  (( _var_avail < 512000 )) && { log ERROR "Insufficient disk space on /var"; exit 1 }

  pkg_add -U ldns-utils ruby%3.4 zap 2>/tmp/pkg_add.log \
    || { log ERROR "Package installation failed. See /tmp/pkg_add.log"; exit 1 }

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

  [[ -d /var/www/acme ]] || { log ERROR "/var/www/acme missing"; exit 1 }
  install_static etc/httpd.conf /etc/httpd.conf
  httpd -n -f /etc/httpd.conf || { log ERROR "httpd.conf invalid"; exit 1 }
  /usr/sbin/rcctl enable httpd
  /usr/sbin/rcctl start httpd || { log ERROR "httpd failed"; exit 1 }
  sleep 5
  typeset _httpd_check; _httpd_check=$(/usr/sbin/rcctl check httpd)
  [[ $_httpd_check == *"httpd(ok)"* ]] || { log ERROR "httpd not running"; exit 1 }

  print -r -- test > /var/www/acme/.well-known/acme-challenge/test
  typeset http_status=${$(curl -s -o /dev/null -w "%{http_code}" http://brgen.no/.well-known/acme-challenge/test):-000}
  rm -f /var/www/acme/.well-known/acme-challenge/test
  (( http_status != 200 )) && { log ERROR "httpd pre-flight failed"; exit 1 }

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
      print -r -- "domain $domain {"
      if [[ -n $subdomains ]]; then
        print -r -- "  alternative names {"
        print -r -- "    $domain"
        for sub in ${(s:,:)subdomains}; do print -r -- "    $sub.$domain"; done
        print -r -- "  }"
      fi
      print -r -- "  domain key /etc/ssl/private/$domain.key"
      print -r -- "  domain full chain certificate /etc/ssl/$domain.fullchain.pem"
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
    print -r -- "test_$domain" > /var/www/acme/.well-known/acme-challenge/test_$domain
    typeset http_status=${$(curl -s -o /dev/null -w "%{http_code}" http://$domain/.well-known/acme-challenge/test_$domain):-000}
    rm -f /var/www/acme/.well-known/acme-challenge/test_$domain
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

  if [[ -t 0 ]]; then
    log INFO "Upload Rails apps (brgen, amber, bsdports) to /home/<app>/<app> with Gemfile and database.yml. Press Enter to continue."
    read -r
  else
    log INFO "Non-interactive mode: Ensure Rails apps are uploaded to /home/<app>/<app>"
  fi

  print -r -- stage_1_complete > $STATE_FILE
  log INFO "Stage 1 complete. ns.brgen.no ($BRGEN_IP) authoritative with DNSSEC. Submit DS from /var/nsd/zones/master/*.ds to Domeneshop.no. Test: '/usr/bin/dig @$BRGEN_IP brgen.no SOA', '/usr/bin/dig @$BRGEN_IP denvr.us A', '/usr/bin/dig DS brgen.no +short'. Wait 24-48h, then 'doas zsh openbsd.sh --resume'."
  exit 0
}
