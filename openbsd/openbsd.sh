#!/usr/bin/env zsh
# Configures OpenBSD 7.7 for NSD & DNSSEC, Ruby on Rails, PF firewall, and minimal OpenSMTPD.
# Usage: doas zsh openbsd.sh [--help | --resume]

set -e
setopt err_exit no_unset nullglob
zmodload zsh/regex

# Configuration settings
BRGEN_IP="46.23.95.45"            # ns.brgen.no, primary nameserver
HYP_IP="194.63.248.53"            # ns.hyp.net, external secondary
EMAIL_ADDRESS="bergen@pub.attorney"  # Email address for OpenSMTPD
STATE_FILE="./openbsd_setup_state"   # Runtime state file
typeset -A APP_PORTS              # Rails app port mappings
typeset -A FAILED_CERTS           # Failed certificate tracking

# Validate IPs
[[ $BRGEN_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || { print -r -- "ERROR: Invalid BRGEN_IP" >&2; exit 1 }
[[ $HYP_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || { print -r -- "ERROR: Invalid HYP_IP" >&2; exit 1 }

# Rails applications
ALL_APPS=(
  brgen:brgen.no
  amber:amberapp.com
  bsdports:bsdports.org
)

# Domain list for DNS
ALL_DOMAINS=(
  brgen.no:markedsplass,playlist,dating,tv,takeaway,maps
  longyearbyn.no:markedsplass,playlist,dating,tv,takeaway,maps
  oshlo.no:markedsplass,playlist,dating,tv,takeaway,maps
  stvanger.no:markedsplass,playlist,dating,tv,takeaway,maps
  trmso.no:markedsplass,playlist,dating,tv,takeaway,maps
  trndheim.no:markedsplass,playlist,dating,tv,takeaway,maps
  reykjavk.is:markadur,playlist,dating,tv,takeaway,maps
  kbenhvn.dk:markedsplads,playlist,dating,tv,takeaway,maps
  gtebrg.se:marknadsplats,playlist,dating,tv,takeaway,maps
  mlmoe.se:marknadsplats,playlist,dating,tv,takeaway,maps
  stholm.se:marknadsplats,playlist,dating,tv,takeaway,maps
  hlsinki.fi:markkinapaikka,playlist,dating,tv,takeaway,maps
  brmingham.uk:marketplace,playlist,dating,tv,takeaway,maps
  cardff.uk:marketplace,playlist,dating,tv,takeaway,maps
  edinbrgh.uk:marketplace,playlist,dating,tv,takeaway,maps
  glasgw.uk:marketplace,playlist,dating,tv,takeaway,maps
  lndon.uk:marketplace,playlist,dating,tv,takeaway,maps
  lverpool.uk:marketplace,playlist,dating,tv,takeaway,maps
  mnchester.uk:marketplace,playlist,dating,tv,takeaway,maps
  amstrdam.nl:marktplaats,playlist,dating,tv,takeaway,maps
  rottrdam.nl:marktplaats,playlist,dating,tv,takeaway,maps
  utrcht.nl:marktplaats,playlist,dating,tv,takeaway,maps
  brssels.be:marche,playlist,dating,tv,takeaway,maps
  zrich.ch:marktplatz,playlist,dating,tv,takeaway,maps
  lchtenstein.li:marktplatz,playlist,dating,tv,takeaway,maps
  frankfrt.de:marktplatz,playlist,dating,tv,takeaway,maps
  brdeaux.fr:marche,playlist,dating,tv,takeaway,maps
  mrseille.fr:marche,playlist,dating,tv,takeaway,maps
  mlan.it:mercato,playlist,dating,tv,takeaway,maps
  lisbon.pt:mercado,playlist,dating,tv,takeaway,maps
  wrsawa.pl:marktplatz,playlist,dating,tv,takeaway,maps
  gdnsk.pl:marktplatz,playlist,dating,tv,takeaway,maps
  austn.us:marketplace,playlist,dating,tv,takeaway,maps
  chcago.us:marketplace,playlist,dating,tv,takeaway,maps
  denvr.us:marketplace,playlist,dating,tv,takeaway,maps
  dllas.us:marketplace,playlist,dating,tv,takeaway,maps
  dnver.us:marketplace,playlist,dating,tv,takeaway,maps
  dtroit.us:marketplace,playlist,dating,tv,takeaway,maps
  houstn.us:marketplace,playlist,dating,tv,takeaway,maps
  lsangeles.com:marketplace,playlist,dating,tv,takeaway,maps
  mnnesota.com:marketplace,playlist,dating,tv,takeaway,maps
  newyrk.us:marketplace,playlist,dating,tv,takeaway,maps
  prtland.com:marketplace,playlist,dating,tv,takeaway,maps
  wshingtondc.com:marketplace,playlist,dating,tv,takeaway,maps
  pub.healthcare
  pub.attorney
  freehelp.legal
  bsdports.org
  bsddocs.org
  discordb.org
  privcam.no
  foodielicio.us
  stacyspassion.com
  antibettingblog.com
  anticasinoblog.com
  antigamblingblog.com
  foball.no
)

# Zsh completion function
_openbsd_sh() {
  _arguments \
    '--help[Show usage information]' \
    '--resume[Resume with Stage 2]'
}

# Utility functions

generate_random_port() {
  # Generate random port (10000–60000), ensuring it’s free
  local port
  while :; do
    port=$((RANDOM % 50000 + 10000))
    (( ! $(netstat -an | grep -c "\.$port ") )) && echo $port && break
  done
}

cleanup_nsd() {
  # Stop nsd and free port 53
  print -r -- "Cleaning nsd(8)" >&2
  [[ -d /var/nsd ]] || { print -r -- "ERROR: /var/nsd missing" >&2; exit 1 }
  timeout 5 rcctl stop nsd || print -r -- "Warning: rcctl stop nsd failed" >&2
  timeout 5 zap -f nsd || print -r -- "Warning: zap -f nsd failed" >&2
  sleep 2
  (( $(netstat -an -p udp | grep -c "$BRGEN_IP.53") )) && {
    print -r -- "ERROR: Port 53 in use" >&2
    exit 1
  }
  print -r -- "Port 53 free" >&2
}

verify_nsd() {
  # Verify nsd for all domains
  print -r -- "Verifying nsd(8) for all domains" >&2
  for domain in ${ALL_DOMAINS[*]%%:*}; do
    local dig_output=${$(dig @"$BRGEN_IP" "$domain" A +short):-}
    (( ${#dig_output} == 0 || dig_output != $BRGEN_IP )) && {
      print -r -- "ERROR: nsd(8) not authoritative for $domain" >&2
      exit 1
    }
    (( ! ${$(dig @"$BRGEN_IP" "$domain" DNSKEY +short):-} )) && {
      print -r -- "ERROR: DNSSEC not enabled for $domain" >&2
      exit 1
    }
  done
  print -r -- "nsd(8) verified with DNSSEC" >&2
}

check_dns_propagation() {
  # Check external DNS propagation
  print -r -- "Checking DNS propagation" >&2
  local resolvers=(8.8.8.8 1.1.1.1 9.9.9.9)
  for resolver in $resolvers; do
    if dig @$resolver brgen.no SOA +short | grep -q "ns.brgen.no."; then
      print -r -- "DNS propagation verified via $resolver" >&2
      return 0
    fi
  done
  print -r -- "ERROR: DNS propagation incomplete. Check glue records." >&2
  exit 1
}

retry_failed_certs() {
  # Retry failed certificates
  print -r -- "Retrying failed certificates" >&2
  for domain in ${(k)FAILED_CERTS}; do
    local dns_check=${$(dig @"$BRGEN_IP" "$domain" A +short):-}
    if [[ $dns_check != $BRGEN_IP ]]; then
      print -r -- "Warning: DNS for $domain failed" >&2
      continue
    fi
    print -r -- "retry_$domain" > "/var/www/acme/.well-known/acme-challenge/retry_$domain"
    local test_url="http://$domain/.well-known/acme-challenge/retry_$domain"
    local http_status=${$(curl -s -o /dev/null -w "%{http_code}" "$test_url"):-000}
    rm -f "/var/www/acme/.well-known/acme-challenge/retry_$domain"
    if [[ $http_status != 200 ]]; then
      print -r -- "Warning: HTTP test for $domain failed" >&2
      continue
    fi
    if acme-client -v -f /etc/acme-client.conf "$domain"; then
      unset FAILED_CERTS[$domain]
      generate_tlsa_record "$domain"
    else
      print -r -- "Warning: Retry failed for $domain" >&2
    fi
  done
}

generate_tlsa_record() {
  # Generate TLSA record for a domain
  local domain=$1 cert=/etc/ssl/$domain.fullchain.pem zonefile=/var/nsd/zones/master/$domain.zone
  local tlsa_record

  [[ ! -f $cert ]] && { print -r -- "Warning: Certificate for $domain not found" >&2; return 1 }
  tlsa_record=${$(openssl x509 -noout -pubkey -in "$cert" | openssl pkey -pubin -outform der 2>/dev/null | openssl dgst -sha256 2>/dev/null | awk '{print $2}'):-}
  (( ! $#tlsa_record )) && { print -r -- "ERROR: TLSA generation failed for $domain" >&2; exit 1 }
  print -r -- "_443._tcp.$domain. IN TLSA 3 1 1 $tlsa_record" >> "$zonefile"
  sign_zone "$domain"
  print -r -- "TLSA updated for $domain" >&2
}

sign_zone() {
  # Sign a zone with DNSSEC
  local domain=$1 zonefile=/var/nsd/zones/master/$domain.zone signed_zonefile=/var/nsd/zones/master/$domain.zone.signed
  local zsk=/var/nsd/zones/master/K$domain.+013+zsk.key ksk=/var/nsd/zones/master/K$domain.+013+ksk.key

  [[ -f $zsk && -f $ksk ]] || { print -r -- "ERROR: ZSK or KSK missing for $domain" >&2; exit 1 }
  ldns-signzone -n -p -s ${$(head -c 16 /dev/random | sha1):-} "$zonefile" "$zsk" "$ksk"
  if ! nsd-checkzone "$domain" "$signed_zonefile"; then
    print -r -- "ERROR: Signed zone invalid for $domain" >&2
    exit 1
  fi
  nsd-control reload
}

# Stage 1: DNS and Certificates

stage_1() {
  print -r -- "Starting Stage 1: DNS and Certificates" >&2

  # Check disk space
  (( $(df -k / | awk 'NR==2 {print $4}') < 100000 )) && {
    print -r -- "ERROR: Insufficient disk space on /" >&2
    exit 1
  }

  # Install packages
  pkg_add -U ldns-utils ruby-3.3.5 postgresql-server redis zap 2> /tmp/pkg_add.log || {
    print -r -- "ERROR: Package installation failed. See /tmp/pkg_add.log" >&2
    exit 1
  }

  # Check pf status
  if grep -q "pf=NO" /etc/rc.conf.local 2>/dev/null; then
    print -r -- "WARNING: pf disabled in rc.conf.local" >&2
  fi

  # Validate interface
  if ! ifconfig vio0 >/dev/null 2>&1; then
    print -r -- "ERROR: Interface vio0 not found" >&2
    exit 1
  fi

  # Enable pf
  pfctl -d || print -r -- "Warning: pf disable failed" >&2
  pfctl -e || { print -r -- "ERROR: pf enable failed" >&2; exit 1 }

  # Configure minimal pf
  cat > /etc/pf.conf <<'EOF'
# Minimal PF for DNS in Stage 1 (pf.conf(5))
ext_if="vio0"
set skip on lo
pass in on $ext_if inet proto { tcp, udp } to $BRGEN_IP port 53
pass out on $ext_if inet proto udp to $HYP_IP port 53
EOF
  pfctl -nf /etc/pf.conf || { print -r -- "ERROR: pf.conf invalid" >&2; exit 1 }
  pfctl -f /etc/pf.conf || { print -r -- "ERROR: pf failed" >&2; exit 1 }

  # Clean NSD directories
  [[ -d /var/nsd/etc ]] || { print -r -- "ERROR: /var/nsd/etc missing" >&2; exit 1 }
  [[ -d /var/nsd/zones/master ]] || { print -r -- "ERROR: /var/nsd/zones/master missing" >&2; exit 1 }
  rm -rf /var/nsd/etc/*(/) /var/nsd/zones/master/*(/)

  # Configure NSD
  cat > /var/nsd/etc/nsd.conf <<EOF
# NSD for DNSSEC (nsd.conf(5))
server:
  ip-address: $BRGEN_IP
  hide-version: yes
  verbosity: 1
  zonesdir: "/var/nsd/zones/master"
remote-control:
  control-enable: yes
  control-interface: 127.0.0.1
EOF
  for domain in ${ALL_DOMAINS[*]%%:*}; do
    cat >> /var/nsd/etc/nsd.conf <<EOF
zone:
  name: "$domain"
  zonefile: "$domain.zone.signed"
  provide-xfr: $HYP_IP NOKEY
  notify: $HYP_IP NOKEY
EOF
  done
  nsd-checkconf /var/nsd/etc/nsd.conf || { print -r -- "ERROR: nsd.conf invalid" >&2; exit 1 }

  # Check entropy
  (( $(sysctl -n kern.entropy.available) < 256 )) && {
    print -r -- "ERROR: Low entropy for DNSSEC key generation" >&2
    exit 1
  }

  # Generate zone files
  local serial=${$(date +%Y%m%d%H):-}
  for domain_entry in $ALL_DOMAINS; do
    local domain=${domain_entry[(ws:*:)1]} subdomains=${${(s:*:)domain_entry}[-1]}
    cat > /var/nsd/zones/master/$domain.zone <<EOF
\$ORIGIN $domain.
\$TTL 3600
@ IN SOA ns.brgen.no. hostmaster.$domain. (
    $serial 1800 900 604800 86400)
@ IN NS ns.brgen.no.
@ IN NS ns.hyp.net.
@ IN A $BRGEN_IP
@ IN MX 10 mail.$domain.
mail IN A $BRGEN_IP
EOF
    [[ $domain = brgen.no ]] && print -r -- "ns IN A $BRGEN_IP" >> /var/nsd/zones/master/$domain.zone
    if [[ -n $subdomains && $subdomains != $domain ]]; then
      for subdomain in ${(s:,:):-$subdomains}; do
        print -r -- "$subdomain IN A $BRGEN_IP" >> /var/nsd/zones/master/$domain.zone
      done
    fi
    nsd-checkzone "$domain" /var/nsd/zones/master/$domain.zone || {
      print -r -- "ERROR: Zone invalid for $domain" >&2
      exit 1
    }
    # Generate DNSSEC keys
    local zsk ksk
    zsk=${$(ldns-keygen -a ECDSAP256SHA256 -b 2048 "$domain")##K}
    ksk=${$(ldns-keygen -k -a ECDSAP256SHA256 -b 2048 "$domain")##K}
    mv /var/nsd/zones/master/K$domain.* /var/nsd/zones/master/
    sign_zone "$domain"
    ldns-key2ds -n -2 /var/nsd/zones/master/$domain.zone.signed > /var/nsd/zones/master/$domain.ds
    chown _nsd:_nsd /var/nsd/zones/master/*
    chmod 640 /var/nsd/zones/master/*
  done

  # Start NSD
  cleanup_nsd
  rcctl enable nsd
  local retries=0 max_retries=2
  while (( retries <= max_retries )); do
    if timeout 10 rcctl start nsd; then
      break
    fi
    (( retries++ ))
    (( retries <= max_retries )) && cleanup_nsd || {
      print -r -- "ERROR: nsd failed" >&2
      exit 1
    }
  done
  sleep 5
  rcctl check nsd | grep -q "nsd(ok)" || { print -r -- "ERROR: nsd not running" >&2; exit 1 }
  verify_nsd

  # Configure HTTP
  [[ -d /var/www/acme ]] || { print -r -- "ERROR: /var/www/acme missing" >&2; exit 1 }
  cat > /etc/httpd.conf <<'EOF'
# HTTP for ACME (httpd.conf(5))
server "acme" {
  listen on $BRGEN_IP port 80
  location "/.well-known/acme-challenge/*" {
    root "/acme"
    request strip 2
  }
  location "*" {
    block return 301 "https://$HTTP_HOST$REQUEST_URI"
  }
}
EOF
  httpd -n -f /etc/httpd.conf || { print -r -- "ERROR: httpd.conf invalid" >&2; exit 1 }
  rcctl enable httpd
  rcctl start httpd || { print -r -- "ERROR: httpd failed" >&2; exit 1 }
  sleep 5
  rcctl check httpd | grep -q "httpd(ok)" || { print -r -- "ERROR: httpd not running" >&2; exit 1 }

  # Verify HTTP
  print -r -- test > /var/www/acme/.well-known/acme-challenge/test
  local http_status=${$(curl -s -o /dev/null -w "%{http_code}" http://brgen.no/.well-known/acme-challenge/test):-000}
  rm -f /var/www/acme/.well-known/acme-challenge/test
  (( http_status != 200 )) && { print -r -- "ERROR: httpd pre-flight failed" >&2; exit 1 }

  # Set up ACME
  [[ ! -f /etc/acme/letsencrypt_privkey.pem ]] && openssl genpkey -algorithm RSA -out /etc/acme/letsencrypt_privkey.pem -pkeyopt rsa_keygen_bits:4096
  chown root:_acme /etc/acme/letsencrypt_privkey.pem
  chmod 640 /etc/acme/letsencrypt_privkey.pem
  cat > /etc/acme-client.conf <<'EOF'
# ACME for Let's Encrypt (acme-client.conf(5))
authority letsencrypt {
  api url "https://acme-v02.api.letsencrypt.org/directory"
  account key "/etc/acme/letsencrypt_privkey.pem"
}
EOF
  for domain_entry in $ALL_DOMAINS; do
    local domain=${domain_entry[(ws:*:)1]} subdomains=${${(s:*:)domain_entry}[-1]}
    local subdomain_list=${${(s:,:):-$subdomains}:+${(j:, :)subdomains}}
    cat >> /etc/acme-client.conf <<EOF
domain $domain {
  alternative names { $subdomain_list }
  domain key /etc/ssl/private/$domain.key
  domain full chain certificate /etc/ssl/$domain.fullchain.pem
  sign with letsencrypt
  challengedir "/var/www/acme"
}
EOF
  done
  acme-client -n -f /etc/acme-client.conf || { print -r -- "ERROR: acme-client.conf invalid" >&2; exit 1 }

  # Issue certificates
  for domain_entry in $ALL_DOMAINS; do
    local domain=${domain_entry[(ws:*:)1]}
    local dns_check=${$(dig @"$BRGEN_IP" "$domain" A +short):-}
    if [[ $dns_check != $BRGEN_IP ]]; then
      print -r -- "Warning: DNS for $domain failed" >&2
      FAILED_CERTS[$domain]=1
      continue
    fi
    print -r -- "test_$domain" > /var/www/acme/.well-known/acme-challenge/test_$domain
    local http_status=${$(curl -s -o /dev/null -w "%{http_code}" http://$domain/.well-known/acme-challenge/test_$domain):-000}
    rm -f /var/www/acme/.well-known/acme-challenge/test_$domain
    if [[ $http_status != 200 ]]; then
      print -r -- "Warning: HTTP test for $domain failed" >&2
      FAILED_CERTS[$domain]=1
      continue
    fi
    if acme-client -v -f /etc/acme-client.conf "$domain"; then
      generate_tlsa_record "$domain"
    else
      print -r -- "Warning: Certificate issuance failed for $domain" >&2
      FAILED_CERTS[$domain]=1
    fi
  done
  (( $#FAILED_CERTS )) && retry_failed_certs

  # Schedule renewals
  local crontab_tmp=/tmp/crontab_tmp
  crontab -l 2>/dev/null > $crontab_tmp || :
  print -r -- "0 2 * * 1 /bin/zsh -c 'for domain in ${ALL_DOMAINS[*]%%:*}; do acme-client -v -f /etc/acme-client.conf \$domain && rcctl reload relayd && generate_tlsa_record \$domain; done'" >> $crontab_tmp
  crontab $crontab_tmp || { print -r -- "ERROR: Crontab update failed" >&2; exit 1 }
  rm $crontab_tmp

  # Pause for Rails upload
  if [[ -t 0 ]]; then
    print -r -- "Upload Rails apps (brgen, amber, bsdports) to /home/<app>/<app> with Gemfile and database.yml. Press Enter to continue." >&2
    read -r
  else
    print -r -- "Non-interactive mode: Ensure Rails apps are uploaded to /home/<app>/<app>" >&2
  fi

  print -r -- stage_1_complete > $STATE_FILE
  print -r -- "Stage 1 complete. ns.brgen.no ($BRGEN_IP) authoritative with DNSSEC. Submit DS from /var/nsd/zones/master/*.ds to Domeneshop.no. Test: 'dig @$BRGEN_IP brgen.no SOA', 'dig @$BRGEN_IP denvr.us A', 'dig DS brgen.no +short'. Wait 24–48h, then 'doas zsh openbsd.sh --resume'." >&2
  exit 0
}

# Service management functions

setup_services() {
  # Start core services, but only enable relayd (don't start it yet)
  print -r -- "Setting up services" >&2
  
  # Start SMTP
  rcctl enable smtpd
  rcctl start smtpd || { print -r -- "ERROR: smtpd failed" >&2; exit 1 }
  sleep 5
  rcctl check smtpd | grep -q "smtpd(ok)" || { print -r -- "ERROR: smtpd not running" >&2; exit 1 }

  # Test SMTP
  if ! timeout 5 telnet $BRGEN_IP 25 >/dev/null 2>&1; then
    print -r -- "Warning: SMTP port 25 not responding" >&2
  fi

  # Start PostgreSQL
  rcctl enable postgresql
  rcctl start postgresql || { print -r -- "ERROR: PostgreSQL failed" >&2; exit 1 }
  sleep 5
  rcctl check postgresql | grep -q "postgresql(ok)" || { print -r -- "ERROR: PostgreSQL not running" >&2; exit 1 }

  # Start Redis
  rcctl enable redis
  rcctl start redis || { print -r -- "ERROR: Redis failed" >&2; exit 1 }
  sleep 5
  rcctl check redis | grep -q "redis(ok)" || { print -r -- "ERROR: Redis not running" >&2; exit 1 }

  # Only enable relayd for boot, don't start it yet (config doesn't exist)
  rcctl enable relayd
  print -r -- "Services configured. relayd enabled but not started (awaiting configuration)" >&2
}

configure_relayd() {
  # Validate APP_PORTS array is populated
  if (( ${#APP_PORTS} == 0 )); then
    print -r -- "ERROR: APP_PORTS array is empty. Rails apps must be deployed first." >&2
    exit 1
  fi

  print -r -- "Configuring relayd with ${#APP_PORTS} app(s)" >&2

  # Configure relayd
  cat > /etc/relayd.conf <<'EOF'
# relayd for HTTPS (relayd.conf(5))
ext_if=$BRGEN_IP
table <web> { $BRGEN_IP }
http protocol https {
  tls { no tlsv1.0, ciphers HIGH:!aNULL }
  header append Strict-Transport-Security max-age=31536000; includeSubDomains; preload
  return error
}
EOF
  for app_entry in $ALL_APPS; do
    local app=${app_entry[(ws:*:)1]} port=$APP_PORTS[$app]
    cat >> /etc/relayd.conf <<EOF
table <$app> { $BRGEN_IP port $port }
relay $app {
  listen on \$ext_if port 443 tls
  protocol https
  forward to <$app> port $port check http "/" code 200
}
EOF
  done

  # Test relayd configuration before starting
  relayd -n -f /etc/relayd.conf || { print -r -- "ERROR: relayd.conf invalid" >&2; exit 1 }
  print -r -- "relayd configuration valid" >&2

  # Allow Rails apps to start fully
  sleep 10
  
  # Start relayd service
  rcctl start relayd || { print -r -- "ERROR: relayd failed to start" >&2; exit 1 }
  sleep 5
  rcctl check relayd | grep -q "relayd(ok)" || { print -r -- "ERROR: relayd not running" >&2; exit 1 }
  print -r -- "relayd started successfully" >&2
}

# Stage 2: Services and Rails Apps

stage_2() {
  print -r -- "Starting Stage 2: Services and Apps" >&2

  check_dns_propagation

  # Check memory
  (( $(vmstat -s | awk '/free memory/{print $1}') < 512000 )) && {
    print -r -- "ERROR: Insufficient free memory" >&2
    exit 1
  }

  # Configure PF
  cat > /etc/pf.conf <<'EOF'
# PF for DNS, HTTP/HTTPS, SSH, SMTP (pf.conf(5))
ext_if="vio0"
set skip on lo
set block-policy return
set loginterface $ext_if
set reassemble yes
set limit { states 10000, frags 5000 }
block log all
scrub in all
table <bruteforce> persist
block quick from <bruteforce>
pass out quick on $ext_if all
pass in on $ext_if inet proto tcp to $ext_if port 22 keep state \
  (max-src-conn 15, max-src-conn-rate 5/3, overload <bruteforce> flush global)
pass in on $ext_if inet proto { tcp, udp } to $BRGEN_IP port 53 log (all)
pass in on $ext_if inet proto tcp to $BRGEN_IP port { 80, 443 } log (all)
pass out on $ext_if inet proto tcp to any port 25
EOF
  pfctl -nf /etc/pf.conf || { print -r -- "ERROR: pf.conf invalid" >&2; exit 1 }
  pfctl -f /etc/pf.conf || { print -r -- "ERROR: pf failed" >&2; exit 1 }

  # Configure OpenSMTPD
  cat > /etc/mail/smtpd.conf <<'EOF'
# OpenSMTPD for outbound email (smtpd.conf(5))
table aliases file:/etc/mail/aliases
listen on $BRGEN_IP port 25 tls
action outbound relay
match from any for any action outbound
queue compression
EOF
  smtpd -n -f /etc/mail/smtpd.conf || { print -r -- "ERROR: smtpd.conf invalid" >&2; exit 1 }
  [[ ! -f /etc/ssl/private/smtp.key ]] && openssl genpkey -algorithm RSA -out /etc/ssl/private/smtp.key -pkeyopt rsa_keygen_bits:4096
  [[ ! -f /etc/ssl/smtp.crt ]] && openssl req -x509 -new -key /etc/ssl/private/smtp.key -out /etc/ssl/smtp.crt -days 365 -subj "/CN=mail.pub.attorney"
  chmod 640 /etc/ssl/private/smtp.key /etc/ssl/smtp.crt

  # Configure PostgreSQL
  mkdir -p /var/postgresql/data
  chown _postgresql:_postgresql /var/postgresql/data
  chmod 700 /var/postgresql/data
  su -l _postgresql -c "initdb -D /var/postgresql/data -U postgres -A scram-sha-256 -E UTF8" || {
    print -r -- "ERROR: PostgreSQL init failed" >&2
    exit 1
  }
  cat > /var/postgresql/data/postgresql.conf <<'EOF'
# PostgreSQL (postgresql.conf(5))
listen_addresses = 'localhost'
shared_buffers = 256MB
EOF
  cat > /var/postgresql/data/pg_hba.conf <<'EOF'
# PostgreSQL auth (pg_hba.conf(5))
local   all   all                    trust
host    all   all   127.0.0.1/32   scram-sha-256
EOF

  # Configure Redis
  mkdir -p /var/redis
  chown _redis:_redis /var/redis
  chmod 700 /var/redis
  cat > /etc/redis.conf <<'EOF'
# Redis (redis.conf(5))
bind 127.0.0.1
port 6379
dir /var/redis/
maxmemory 512mb
EOF
  redis-server --dry-run /etc/redis.conf || { print -r -- "ERROR: redis.conf invalid" >&2; exit 1 }

  setup_services

  # Deploy Rails apps
  for app_entry in $ALL_APPS; do
    local app=${app_entry[(ws:*:)1]} domain=${${(s:*:)app_entry}[-1]}
    local port=${APP_PORTS[$app]:=$(generate_random_port)}
    APP_PORTS[$app]=$port
    local app_dir=/home/$app/$app
    useradd -m -s /bin/ksh -L rails $app 2>/dev/null || :
    [[ ! -f $app_dir/Gemfile || ! -f $app_dir/config/database.yml ]] && {
      print -r -- "ERROR: Missing Gemfile or database.yml in $app_dir" >&2
      exit 1
    }
    chown -R $app:$app /home/$app
    su -l $app -c "gem install --user-install rails bundler falcon" || {
      print -r -- "ERROR: gem install failed for $app" >&2
      exit 1
    }
    su -l $app -c "cd $app_dir && bundle config set --local without 'development test' && bundle check || bundle install" || {
      print -r -- "ERROR: bundle install failed for $app" >&2
      exit 1
    }
    su -l _postgresql -c "createdb ${app}_production" || {
      print -r -- "ERROR: createdb failed for $app" >&2
      exit 1
    }
    su -l $app -c "cd $app_dir && bundle exec rails db:migrate" || {
      print -r -- "ERROR: rails db:migrate failed for $app" >&2
      exit 1
    }
    cat > /etc/rc.d/$app <<EOF
#!/bin/ksh
# rc.d for $app (rc.d(8))
daemon="/bin/ksh -c 'cd $app_dir && export RAILS_ENV=production && \$HOME/.gem/ruby/*/bin/bundle exec \$HOME/.gem/ruby/*/bin/falcon -b tcp://127.0.0.1:$port'"
daemon_user="$app"
. /etc/rc.d/rc.subr
rc_cmd \$1
EOF
    chmod 755 /etc/rc.d/$app
    rcctl enable $app
    rcctl start $app || { print -r -- "ERROR: $app failed" >&2; exit 1 }
    sleep 5
    rcctl check $app | grep -q "$app(ok)" || { print -r -- "ERROR: $app not running" >&2; exit 1 }
  done

  # Configure and start relayd now that APP_PORTS is populated
  configure_relayd

  print -r -- stage_2_complete > $STATE_FILE
  print -r -- "Stage 2 complete. Setup complete. Test: 'curl https://brgen.no', 'curl https://amberapp.com', 'curl https://bsdports.org'." >&2
  exit 0
}

# Main execution
main() {
  [[ -f $STATE_FILE && ! -r $STATE_FILE ]] && { print -r -- "ERROR: $STATE_FILE not readable" >&2; exit 1 }
  if [[ $1 = --help ]]; then
    print -r -- "Sets up OpenBSD 7.7 for Rails with DNSSEC and minimal OpenSMTPD.\nUsage: doas zsh openbsd.sh [--help | --resume]"
    exit 0
  fi
  if [[ $1 = --resume && -f $STATE_FILE && $(<$STATE_FILE) = stage_1_complete ]]; then
    stage_2
  elif [[ -z $1 && ! -f $STATE_FILE ]]; then
    stage_1
  else
    print -r -- "ERROR: Invalid state. Use --help, --resume, or remove $STATE_FILE." >&2
    exit 1
  fi
}

main "$@"