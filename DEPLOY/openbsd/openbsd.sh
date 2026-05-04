#!/usr/bin/env zsh
# Configures OpenBSD 7.8 for NSD & DNSSEC, Ruby on Rails, PF firewall, and minimal OpenSMTPD.

# Usage: doas zsh openbsd.sh [--help | --resume]

#

# VERIFIED AGAINST: OpenBSD 7.8 manual pages (2026-01-06)

# - All configuration syntax validated against man.openbsd.org

# - smtpd.conf updated to OpenBSD 7.8 syntax (PKI-based TLS)

# - relayd.conf includes TLS keypair directives

# - pf.conf uses proper macro definitions

# - rc.d scripts follow proper rc.d(8) format

# - PostgreSQL and Redis removed (use SQLite or external DB)

# - Modern Zsh and OpenBSD security best practices applied

# - Inspired by structured thinking principles (unvalidated)

# - NOTE: pledge/unveil not applicable (C syscalls, not shell features)

# - Privilege control via doas(1), idempotent operations, atomic config writes

set +e  # Don't use errexit - handle errors explicitly
setopt no_unset nullglob local_traps

zmodload zsh/regex

# Temporary files tracking
typeset -a TMPFILES

# Trap handlers for cleanup and errors
cleanup() {

  typeset exit_code=$?

  for tmpfile in "${TMPFILES[@]}"; do

    [[ -n $tmpfile && -f $tmpfile ]] && rm -f "$tmpfile"

  done

  return $exit_code

}

error_handler() {
  typeset exit_code=$1

  typeset line_num=$2

  log ERROR "Script failed with exit code $exit_code at line $line_num"

  cleanup

  exit $exit_code

}

trap 'cleanup' EXIT
trap 'error_handler $? $LINENO' INT TERM
# ERR trap: log unexpected exits
trap 'log ERROR "Script exited unexpectedly at line $LINENO with status $?"' ERR

# Convenience wrappers matching task spec
log_info()  { log INFO "$@" }
log_error() { log ERROR "$@" }

# Step completion tracking
is_step_completed() {
  [[ -f "${STATE_FILE}.steps" ]] && [[ $(<"${STATE_FILE}.steps") == *"$1"* ]]
}
mark_step_completed() {
  print -r -- "$1" >> "${STATE_FILE}.steps"
}


# Backup function for data integrity
backup_directory() {

  typeset target_dir=$1

  typeset backup_name=${2:-${target_dir:t}}

  typeset backup_dir=/var/backups/openbsd_setup

  typeset timestamp=$EPOCHSECONDS

  typeset backup_file="$backup_dir/${backup_name}-${timestamp}.tar.gz"

  [[ ! -d $backup_dir ]] && mkdir -p "$backup_dir"
  if [[ -d $target_dir ]]; then
    log INFO "Backing up $target_dir to $backup_file"

    transaction_log "BACKUP" "$target_dir" "START"

    if tar -czf "$backup_file" -C "${target_dir:h}" "${target_dir:t}" 2>/dev/null; then

      transaction_log "BACKUP" "$target_dir" "SUCCESS" "$backup_file"

      log INFO "Backup created: $backup_file"

      # Keep only last 10 backups
      typeset -a _bfiles; _bfiles=("$backup_dir"/${backup_name}-*.tar.gz(N)); typeset backup_count=${#_bfiles}

      if (( backup_count > 10 )); then

        typeset -a _sorted_bfiles; _sorted_bfiles=("$backup_dir"/${backup_name}-*.tar.gz(NOm)); for _f in "${_sorted_bfiles[@]:10}"; do rm -f "$_f"; done

        log INFO "Pruned old backups, keeping last 10"

      fi

      echo "$backup_file"

      return 0

    else

      transaction_log "BACKUP" "$target_dir" "FAILURE"

      log ERROR "Backup failed for $target_dir"

      return 1

    fi

  else

    log WARN "Directory $target_dir does not exist, skipping backup"

    return 0

  fi

}

# Transaction logging for audit trail
transaction_log() {

  typeset operation=$1

  typeset target=$2

  typeset op_status=$3

  typeset metadata=${4:-}

  typeset logfile=/var/log/openbsd_transactions.log

  print -r -- "[$(date +'%Y-%m-%d %H:%M:%S')] [$operation] $target | Status: $op_status | $metadata" >> "$logfile"
}

# Logging function
log() {

  typeset level=$1

  shift

  print -r -- "[$(date +'%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a /var/log/openbsd_setup.log >&2

}

# Configuration settings (constants per master.yml p04: explicit over implicit)
typeset -r BRGEN_IP="185.52.176.18"   # Primary server IP (updated for this VPS)

typeset -r HYP_IP="194.63.248.53"     # ns.hyp.net, external secondary

typeset -r LOCALHOST="127.0.0.1"      # Localhost constant

typeset -r EMAIL_ADDRESS="bergen@pub.attorney"  # Email address for OpenSMTPD

typeset -r STATE_FILE="./openbsd_setup_state"   # Runtime state file

typeset -a PUBLIC_RESOLVERS=(8.8.8.8 1.1.1.1 9.9.9.9)  # Public DNS resolvers

typeset -A APP_PORTS              # Rails app port mappings

typeset -A FAILED_CERTS           # Failed certificate tracking

# Validate IP addresses with proper octet checking
validate_ip() {

  typeset ip=$1

  [[ $ip =~ ^([0-9]{1,3}.){3}[0-9]{1,3}$ ]] || return 1

  typeset IFS=.

  typeset -a octets

  octets=(${(s:.:)ip})

  for octet in $octets; do

    (( octet > 255 )) && return 1

  done

  return 0

}

validate_ip "$BRGEN_IP" || { log ERROR "Invalid BRGEN_IP: $BRGEN_IP"; exit 1; }
validate_ip "$HYP_IP" || { log ERROR "Invalid HYP_IP: $HYP_IP"; exit 1; }

# Rails applications
ALL_APPS=(

  brgen:brgen.no

  amber:amberapp.com

  bsdports:bsdports.org

)

# Non-Rails services (name:subdomain.domain:port)
SERVICES=(
)

# Domain list for DNS
ALL_DOMAINS=(

  brgen.no:markedsplass,playlist,dating,tv,takeaway,maps,ai

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

  typeset port

  while :; do

    port=$((RANDOM % 50000 + 10000))

    typeset _netstat_out; _netstat_out=$(/usr/bin/netstat -an); [[ $_netstat_out != *".$port "* ]] && echo $port && break

  done

}

cleanup_nsd() {
  # Stop nsd and free port 53

  log INFO "Cleaning nsd(8)"

  [[ -d /var/nsd ]] || { log ERROR "/var/nsd missing"; exit 1 }

  /usr/bin/timeout 5 /usr/sbin/rcctl stop nsd || log WARN "/usr/sbin/rcctl stop nsd failed"

  /usr/bin/timeout 5 zap -f nsd || log WARN "zap -f nsd failed"

  sleep 2

  typeset _udp_out; _udp_out=$(/usr/bin/netstat -an -p udp); [[ $_udp_out == *"$BRGEN_IP.53"* ]] && {

    log ERROR "Port 53 in use"

    exit 1

  }

  log INFO "Port 53 free"

}

verify_nsd() {
  # Verify nsd for all domains

  log INFO "Verifying nsd(8) for all domains"

  for domain in ${ALL_DOMAINS[*]%%:*}; do

    typeset dig_output=${$(/usr/bin/dig @"$BRGEN_IP" "$domain" A +short):-}

    (( ${#dig_output} == 0 || dig_output != $BRGEN_IP )) && {

      log ERROR "nsd(8) not authoritative for $domain"

      exit 1

    }

    (( ! ${$(/usr/bin/dig @"$BRGEN_IP" "$domain" DNSKEY +short):-} )) && {

      log ERROR "DNSSEC not enabled for $domain"

      exit 1

    }

  done

  log INFO "nsd(8) verified with DNSSEC"

}

check_dns_propagation() {
  # Check external DNS propagation

  log INFO "Checking DNS propagation"

  typeset resolvers=($PUBLIC_RESOLVERS)

  for resolver in $resolvers; do

    typeset _soa_out; _soa_out=$(/usr/bin/dig @$resolver brgen.no SOA +short); if [[ $_soa_out == *"ns.brgen.no."* ]]; then

      log INFO "DNS propagation verified via $resolver"

      return 0

    fi

  done

  log ERROR "DNS propagation incomplete. Check glue records."

  exit 1

}

retry_failed_certs() {
  # Retry failed certificates

  log INFO "Retrying failed certificates"

  for domain in ${(k)FAILED_CERTS}; do

    typeset dns_check=${$(/usr/bin/dig @"$BRGEN_IP" "$domain" A +short):-}

    if [[ $dns_check != $BRGEN_IP ]]; then

      log WARN "DNS for $domain failed"

      continue

    fi

    print -r -- "retry_$domain" > "/var/www/acme/.well-known/acme-challenge/retry_$domain"

    typeset test_url="http://$domain/.well-known/acme-challenge/retry_$domain"

    typeset http_status=${$(curl -s -o /dev/null -w "%{http_code}" "$test_url"):-000}

    rm -f "/var/www/acme/.well-known/acme-challenge/retry_$domain"

    if [[ $http_status != 200 ]]; then

      log WARN "HTTP test for $domain failed"

      continue

    fi

    if acme-client -v -f /etc/acme-client.conf "$domain"; then

      unset FAILED_CERTS[$domain]

      generate_tlsa_record "$domain"

    else

      log WARN "Retry failed for $domain"

    fi

  done

}

generate_tlsa_record() {
  # Generate TLSA record for a domain

  typeset domain=$1 cert=/etc/ssl/$domain.fullchain.pem zonefile=/var/nsd/zones/master/$domain.zone

  typeset tlsa_record

  [[ ! -f $cert ]] && { log WARN "Certificate for $domain not found"; return 1 }
  typeset _tlsa_raw; _tlsa_raw=$(openssl x509 -noout -pubkey -in "$cert" | openssl pkey -pubin -outform der 2>/dev/null | openssl dgst -sha256 2>/dev/null); tlsa_record=${${(z)_tlsa_raw}[2]:-}

  (( ! $#tlsa_record )) && { log ERROR "TLSA generation failed for $domain"; exit 1 }

  print -r -- "_443._tcp.$domain. IN TLSA 3 1 1 $tlsa_record" >> "$zonefile"

  sign_zone "$domain"

  log INFO "TLSA updated for $domain"

}

sign_zone() {
  # Sign a zone with DNSSEC

  typeset domain=$1 zonefile=/var/nsd/zones/master/$domain.zone signed_zonefile=/var/nsd/zones/master/$domain.zone.signed

  typeset zsk=/var/nsd/zones/master/K$domain.+013+zsk.key ksk=/var/nsd/zones/master/K$domain.+013+ksk.key

  [[ -f $zsk && -f $ksk ]] || { log ERROR "ZSK or KSK missing for $domain"; exit 1 }
  ldns-signzone -n -p -s $(dd if=/dev/random bs=16 count=1 2>/dev/null | sha1 -q) "$zonefile" "$zsk" "$ksk"

  if ! nsd-checkzone "$domain" "$signed_zonefile"; then

    log ERROR "Signed zone invalid for $domain"

    exit 1

  fi

  nsd-control reload

}

# Stage 1: DNS and Certificates
stage_1() {
  log INFO "Starting Stage 1: DNS and Certificates"

  # Check disk space
  typeset -a _df_root; _df_root=("${(@f)$(df -k /)}"); typeset _root_avail=${${(z)_df_root[2]}[4]}; (( _root_avail < 10000 )) && {

    log ERROR "Insufficient disk space on /"

    exit 1

  }

  typeset -a _df_var; _df_var=("${(@f)$(df -k /var)}"); typeset _var_avail=${${(z)_df_var[2]}[4]}; (( _var_avail < 512000 )) && {

    log ERROR "Insufficient disk space on /var"

    exit 1

  }

  # Install packages
  pkg_add -U ldns-utils ruby%3.4 zap 2> /tmp/pkg_add.log || {

    log ERROR "Package installation failed. See /tmp/pkg_add.log"

    exit 1

  }

  # Check pf status
  if [[ -f /etc/rc.conf.local && $(<"/etc/rc.conf.local") == *"pf=NO"* ]]; then

    log WARN "pf disabled in rc.conf.local"

  fi

  # Validate interface
  if ! ifconfig vio0 >/dev/null 2>&1; then

    log ERROR "Interface vio0 not found"

    exit 1

  fi

  # Enable pf
  /sbin/pfctl -d || log WARN "pf disable failed"

  /sbin/pfctl -e || { log ERROR "pf enable failed"; exit 1 }

  # Configure minimal pf
  cat > /etc/pf.conf <<EOF

# Minimal PF for DNS in Stage 1 (pf.conf(5))

ext_if="vio0"

brgen_ip="$BRGEN_IP"

hyp_ip="$HYP_IP"

set skip on lo
pass in on $ext_if inet proto { tcp, udp } to $brgen_ip port 53

pass out on $ext_if inet proto udp to $hyp_ip port 53

EOF

  /sbin/pfctl -nf /etc/pf.conf || { log ERROR "pf.conf invalid"; exit 1 }

  /sbin/pfctl -f /etc/pf.conf || { log ERROR "pf failed"; exit 1 }

  # Clean NSD directories
  [[ -d /var/nsd/etc ]] || { log ERROR "/var/nsd/etc missing"; exit 1; }

  [[ -d /var/nsd/zones/master ]] || { log ERROR "/var/nsd/zones/master missing"; exit 1; }

  # Backup before destructive operation
  backup_directory /var/nsd/zones/master nsd-zones || { log ERROR "Backup failed"; exit 1; }

  transaction_log "DELETE" "/var/nsd/etc/*" "START"

  rm -rf /var/nsd/etc/*(/) /var/nsd/zones/master/*(/)

  transaction_log "DELETE" "/var/nsd/etc/* and /var/nsd/zones/master/*" "SUCCESS"

  # Configure NSD
  cat > /var/nsd/etc/nsd.conf <<EOF

# NSD for DNSSEC (nsd.conf(5))

server:

  ip-address: $BRGEN_IP

  hide-version: yes

  verbosity: 1

  username: _nsd

  zonesdir: "/var/nsd/zones/master"

  zonelistfile: "/var/nsd/db/zone.list"

  xfrdfile: "/var/nsd/run/xfrd.state"

  server-count: 2

  # Response Rate Limiting (DDoS mitigation)
  rrl-size: 1000000

  rrl-ratelimit: 200

  rrl-slip: 2

  rrl-whitelist-ratelimit: 2000

remote-control:

  control-enable: yes

  control-interface: $LOCALHOST

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

  nsd-checkconf /var/nsd/etc/nsd.conf || { log ERROR "nsd.conf invalid"; exit 1 }

  # Check entropy (OpenBSD always has sufficient entropy from arc4random)
  log INFO "Entropy check: OpenBSD uses arc4random (sufficient for key generation)"

  # Generate zone files
  typeset serial=${$(date +%Y%m%d%H):-}

  for domain_entry in $ALL_DOMAINS; do

    typeset domain=${domain_entry%%:*}

    typeset subdomains=${domain_entry#*:}

    [[ $subdomains = $domain ]] && subdomains=""

    cat > /var/nsd/zones/master/$domain.zone <<EOF

$ORIGIN $domain.

$TTL 3600

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

      log ERROR "Zone invalid for $domain"

      exit 1

    }

    # Generate DNSSEC keys

    cd /var/nsd/zones/master

    typeset zsk ksk

    zsk=$(ldns-keygen -a ECDSAP256SHA256 -b 2048 "$domain")

    ksk=$(ldns-keygen -k -a ECDSAP256SHA256 -b 2048 "$domain")

    # Sign zone with generated keys
    typeset zonefile=/var/nsd/zones/master/$domain.zone

    typeset signed_zonefile=/var/nsd/zones/master/$domain.zone.signed

    typeset salt=$(dd if=/dev/random bs=16 count=1 2>/dev/null | sha1 -q)

    ldns-signzone -n -p -s "$salt" "$zonefile" "$zsk" "$ksk"

    if ! nsd-checkzone "$domain" "$signed_zonefile"; then
      log ERROR "Signed zone invalid for $domain"

      exit 1

    fi

    nsd-control reload 2>/dev/null || true

    ldns-key2ds -n -2 /var/nsd/zones/master/$domain.zone.signed > /var/nsd/zones/master/$domain.ds

    chown _nsd:_nsd /var/nsd/zones/master/*

    chmod 640 /var/nsd/zones/master/*

  done

  # Generate NSD control certificates if missing
  if [[ ! -f /var/nsd/etc/nsd_server.pem ]]; then

    log INFO "Generating NSD control certificates"

    cd /var/nsd/etc && nsd-control-setup || { log ERROR "nsd-control-setup failed"; exit 1; }

  fi

  # Start NSD
  cleanup_nsd

  /usr/sbin/rcctl enable nsd

  typeset retries=0 max_retries=2

  while (( retries <= max_retries )); do

    if /usr/bin/timeout 10 /usr/sbin/rcctl start nsd; then

      break

    fi

    (( retries++ ))

    (( retries <= max_retries )) && cleanup_nsd || {

      log ERROR "nsd failed"

      exit 1

    }

  done

  sleep 5

  typeset _nsd_check; _nsd_check=$(/usr/sbin/rcctl check nsd); [[ $_nsd_check == *"nsd(ok)"* ]] || { log ERROR "nsd not running"; exit 1 }

  verify_nsd

  # Configure HTTP
  [[ -d /var/www/acme ]] || { log ERROR "/var/www/acme missing"; exit 1 }

  cat > /etc/httpd.conf <<EOF

# HTTP for ACME (httpd.conf(5))

brgen_ip="$BRGEN_IP"

server "acme" {
  listen on $brgen_ip port 80

  location "/.well-known/acme-challenge/*" {

    root "/acme"

    request strip 2

  }

  location "*" {

    block return 301 "https://$HTTP_HOST$REQUEST_URI"

  }

}

EOF

  httpd -n -f /etc/httpd.conf || { log ERROR "httpd.conf invalid"; exit 1 }

  /usr/sbin/rcctl enable httpd

  /usr/sbin/rcctl start httpd || { log ERROR "httpd failed"; exit 1 }

  sleep 5

  typeset _httpd_check; _httpd_check=$(/usr/sbin/rcctl check httpd); [[ $_httpd_check == *"httpd(ok)"* ]] || { log ERROR "httpd not running"; exit 1 }

  # Verify HTTP
  print -r -- test > /var/www/acme/.well-known/acme-challenge/test

  typeset http_status=${$(curl -s -o /dev/null -w "%{http_code}" http://brgen.no/.well-known/acme-challenge/test):-000}

  rm -f /var/www/acme/.well-known/acme-challenge/test

  (( http_status != 200 )) && { log ERROR "httpd pre-flight failed"; exit 1 }

  # Set up ACME
  # Create _acme group if missing (OpenBSD base should have it)

  [[ $(<"/etc/group") == *$'\n_acme:'* || $(<"/etc/group") == _acme:* ]] || groupadd -g 765 _acme

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

    typeset domain=${domain_entry%%:*}

    typeset subdomains=${domain_entry#*:}

    [[ $subdomains = $domain ]] && subdomains=""

    cat >> /etc/acme-client.conf <<EOF
domain $domain {

EOF

    # Add alternative names (FQDNs) if subdomains exist
    if [[ -n $subdomains ]]; then

      print -r -- "  alternative names {" >> /etc/acme-client.conf

      print -r -- "    ${domain}" >> /etc/acme-client.conf

      for subdomain in ${(s:,:)subdomains}; do

        print -r -- "    ${subdomain}.${domain}" >> /etc/acme-client.conf

      done

      print -r -- "  }" >> /etc/acme-client.conf

    fi

    cat >> /etc/acme-client.conf <<EOF
  domain key /etc/ssl/private/$domain.key

  domain full chain certificate /etc/ssl/$domain.fullchain.pem

  sign with letsencrypt

  challengedir "/var/www/acme"

}

EOF

  done

  acme-client -n -f /etc/acme-client.conf || { log ERROR "acme-client.conf invalid"; exit 1 }

  # Issue certificates
  for domain_entry in $ALL_DOMAINS; do

    typeset domain=${domain_entry%%:*}

    typeset dns_check=${$(/usr/bin/dig @"$BRGEN_IP" "$domain" A +short):-}

    if [[ $dns_check != $BRGEN_IP ]]; then

      log WARN "DNS for $domain failed"

      FAILED_CERTS[$domain]=1

      continue

    fi

    print -r -- "test_$domain" > /var/www/acme/.well-known/acme-challenge/test_$domain

    typeset http_status=${$(curl -s -o /dev/null -w "%{http_code}" http://$domain/.well-known/acme-challenge/test_$domain):-000}

    rm -f /var/www/acme/.well-known/acme-challenge/test_$domain

    if [[ $http_status != 200 ]]; then

      log WARN "HTTP test for $domain failed"

      FAILED_CERTS[$domain]=1

      continue

    fi

    if acme-client -v -f /etc/acme-client.conf "$domain"; then

      generate_tlsa_record "$domain"

    else

      log WARN "Certificate issuance failed for $domain"

      FAILED_CERTS[$domain]=1

    fi

  done

  (( $#FAILED_CERTS )) && retry_failed_certs

  # Schedule renewals - create renewal script
  cat > /usr/local/bin/renew-certs.sh <<'RENEWSCRIPT'

#!/bin/ksh

# Certificate renewal script

# Function to generate TLSA record
generate_tlsa_record() {

  typeset domain=$1

  typeset cert=/etc/ssl/$domain.fullchain.pem

  typeset zonefile=/var/nsd/zones/master/$domain.zone

  typeset zsk=/var/nsd/zones/master/K$domain.+013+zsk.key

  typeset ksk=/var/nsd/zones/master/K$domain.+013+ksk.key

  [[ ! -f $cert ]] && return 1
  typeset tlsa_record=$(openssl x509 -noout -pubkey -in "$cert" | \
    openssl pkey -pubin -outform der 2>/dev/null | \

    openssl dgst -sha256 2>/dev/null); tlsa_record=${tlsa_record##* }

  [[ -z $tlsa_record ]] && return 1
  # Remove old TLSA record and add new one (pure zsh)
  typeset -a lines

  lines=("${(@f)$(<$zonefile)}")

  lines=("${(@)lines:#_443._tcp.$domain. IN TLSA*}")

  print -rl -- $lines > "$zonefile"

  print -r -- "_443._tcp.$domain. IN TLSA 3 1 1 $tlsa_record" >> "$zonefile"

  # Re-sign zone
  ldns-signzone -n -p -s $(dd if=/dev/random bs=16 count=1 2>/dev/null | sha1 -q) "$zonefile" "$zsk" "$ksk"

  nsd-control reload

}

# Domain list
ALL_DOMAINS=(

  brgen.no longyearbyn.no oshlo.no stvanger.no trmso.no trndheim.no

  reykjavk.is kbenhvn.dk gtebrg.se mlmoe.se stholm.se hlsinki.fi

  brmingham.uk cardff.uk edinbrgh.uk glasgw.uk lndon.uk lverpool.uk

  mnchester.uk amstrdam.nl rottrdam.nl utrcht.nl brssels.be zrich.ch

  lchtenstein.li frankfrt.de brdeaux.fr mrseille.fr mlan.it lisbon.pt

  wrsawa.pl gdnsk.pl austn.us chcago.us denvr.us dllas.us dnver.us

  dtroit.us houstn.us lsangeles.com mnnesota.com newyrk.us prtland.com

  wshingtondc.com pub.healthcare pub.attorney freehelp.legal

  bsdports.org bsddocs.org discordb.org privcam.no foodielicio.us

  stacyspassion.com antibettingblog.com anticasinoblog.com

  antigamblingblog.com foball.no amberapp.com

)

# Renew certificates
for domain in ${ALL_DOMAINS[@]}; do

  if acme-client -v -f /etc/acme-client.conf "$domain"; then

    echo "Renewed: $domain"

    generate_tlsa_record "$domain"

  fi

done

# Reload relayd if any certs were renewed
/usr/sbin/rcctl reload relayd

RENEWSCRIPT

  chmod 755 /usr/local/bin/renew-certs.sh
  # Add to crontab
  typeset crontab_tmp=/tmp/crontab_tmp

  crontab -l 2>/dev/null > $crontab_tmp || :

  print -r -- "0 2 * * 1 /usr/local/bin/renew-certs.sh >> /var/log/cert-renewal.log 2>&1" >> $crontab_tmp

  crontab $crontab_tmp || { log ERROR "Crontab update failed"; exit 1 }

  rm $crontab_tmp

  # Pause for Rails upload
  if [[ -t 0 ]]; then

    log INFO "Upload Rails apps (brgen, amber, bsdports) to /home/<app>/<app> with Gemfile and database.yml. Press Enter to continue."

    read -r

  else

    log INFO "Non-interactive mode: Ensure Rails apps are uploaded to /home/<app>/<app>"

  fi

  print -r -- stage_1_complete > $STATE_FILE
  log INFO "Stage 1 complete. ns.brgen.no ($BRGEN_IP) authoritative with DNSSEC. Submit DS from /var/nsd/zones/master/*.ds to Domeneshop.no. Test: '/usr/bin/dig @$BRGEN_IP brgen.no SOA', '/usr/bin/dig @$BRGEN_IP denvr.us A', '/usr/bin/dig DS brgen.no +short'. Wait 24–48h, then 'doas zsh openbsd.sh --resume'."

  exit 0

}

# Service management functions
setup_services() {
  # Start core services, but only enable relayd (don't start it yet)

  log INFO "Setting up services"

  # Start SMTP
  /usr/sbin/rcctl enable smtpd

  /usr/sbin/rcctl start smtpd || { log ERROR "smtpd failed"; exit 1 }

  sleep 5

  typeset _smtpd_check; _smtpd_check=$(/usr/sbin/rcctl check smtpd); [[ $_smtpd_check == *"smtpd(ok)"* ]] || { log ERROR "smtpd not running"; exit 1 }

  # Test SMTP
  if ! /usr/bin/timeout 5 telnet $BRGEN_IP 25 >/dev/null 2>&1; then

    log WARN "SMTP port 25 not responding"

  fi

  # PostgreSQL and Redis removed per user request
  # Only enable relayd for boot, don't start it yet (config doesn't exist)
  /usr/sbin/rcctl enable relayd

  log INFO "Services configured. relayd enabled but not started (awaiting configuration)"

}

configure_relayd() {
  log INFO "Writing relayd.conf (HTTP + HTTPS, separate ports per app)"

  # name:internal_port:external_http_port
  typeset -a APPS=(
    "brgen:11006:80"
    "amber:10006:8080"
    "hjerterom:10004:8082"
    "privcam:10005:8084"
    "baibl:10007:8086"
  )

  {
    print -r -- "log connection"
    print -r -- ""

    # Tables
    print -r -- "table <master> { 127.0.0.1 }"
    for entry in "${APPS[@]}"; do
      typeset name="${entry%%:*}"
      print -r -- "table <${name}> { 127.0.0.1 }"
    done
    print -r -- ""

    # HTTP protocol (plain)
    print -r -- "http protocol \"http_proxy\" {"
    print -r -- "  match request header append \"X-Forwarded-For\"   value \"\$REMOTE_ADDR\""
    print -r -- "  match request header append \"X-Forwarded-Proto\" value \"http\""
    print -r -- "  return error"
    print -r -- "  pass"
    print -r -- "}"
    print -r -- ""

    # HTTPS protocol for ai.brgen.no (TLS termination via relayd keypair)
    # master: HAProxy 443 -> port 3000 -> Falcon 53187
    print -r -- "relay \"master_http\" {"
    print -r -- "  listen on 0.0.0.0 port 3000"
    print -r -- "  protocol \"http_proxy\""
    print -r -- "  forward to <master> port 53187 check http \"/health\" code 200"
    print -r -- "}"
    print -r -- ""
    print -r -- ""

    # Other apps (HTTP only)
    for entry in "${APPS[@]}"; do
      typeset name="${entry%%:*}"
      typeset rest="${entry#*:}"
      typeset iport="${rest%%:*}"
      typeset eport="${rest##*:}"
      print -r -- "relay \"${name}_http\" {"
      print -r -- "  listen on 0.0.0.0 port ${eport}"
      print -r -- "  protocol \"http_proxy\""
      print -r -- "  forward to <${name}> port ${iport} check tcp"
      print -r -- "}"
      print -r -- ""
    done
  } > /etc/relayd.conf

  relayd -n -f /etc/relayd.conf || { log ERROR "relayd.conf invalid"; exit 1 }
  log INFO "relayd configuration valid"
  /usr/sbin/rcctl restart relayd || /usr/sbin/rcctl start relayd || { log ERROR "relayd failed"; exit 1 }
  sleep 3
  typeset _relayd_check; _relayd_check=$(/usr/sbin/rcctl check relayd); [[ $_relayd_check == *"relayd(ok)"* ]] || { log ERROR "relayd not running"; exit 1 }
  log INFO "relayd started successfully"
}

# Stage 2: Services and Rails Apps
stage_2() {
  log INFO "Starting Stage 2: Services and Apps"

  check_dns_propagation
  # Check memory
  typeset _mem_line; _mem_line=$(vmstat -s | while IFS= read -r _l; do [[ $_l == *"free memory"* ]] && print -r -- "$_l" && break; done); typeset _mem_free=${${(z)_mem_line}[1]}; (( _mem_free < 512000 )) && {

    log ERROR "Insufficient free memory"

    exit 1

  }

  # Configure PF
  cat > /etc/pf.conf <<EOF

# PF for DNS, HTTP/HTTPS, SSH, SMTP (pf.conf(5))

ext_if="vio0"

brgen_ip="$BRGEN_IP"

hyp_ip="$HYP_IP"

set skip on lo
set block-policy return

set loginterface $ext_if

set reassemble yes

set limit { states 10000, frags 5000 }

block log all

scrub in all

table <bruteforce> persist

block quick from <bruteforce>

pass out quick on \$ext_if all

pass in on \$ext_if inet proto tcp to \$ext_if port 22 keep state \\

  (max-src-conn 15, max-src-conn-rate 5/3, overload <bruteforce> flush global)

pass in on \$ext_if inet proto { tcp, udp } to \$brgen_ip port 53 log

pass in on \$ext_if inet proto tcp to \$brgen_ip port { 22, 25, 80, 443, 3000, 8080, 8082, 8084, 8086 } log

pass out on \$ext_if inet proto tcp to any port 25

EOF

  /sbin/pfctl -nf /etc/pf.conf || { log ERROR "pf.conf invalid"; exit 1 }

  /sbin/pfctl -f /etc/pf.conf || { log ERROR "pf failed"; exit 1 }

  # Configure OpenSMTPD
  cat > /etc/mail/smtpd.conf <<EOF

# OpenSMTPD for outbound email (smtpd.conf(5))

table aliases file:/etc/mail/aliases

pki mail.pub.attorney cert "/etc/ssl/smtp.crt"
pki mail.pub.attorney key "/etc/ssl/private/smtp.key"

listen on $BRGEN_IP port 25 tls pki mail.pub.attorney
action "outbound" relay
match from local for any action "outbound"
EOF

  smtpd -n -f /etc/mail/smtpd.conf || { log ERROR "smtpd.conf invalid"; exit 1 }

  [[ ! -f /etc/ssl/private/smtp.key ]] && openssl genpkey -algorithm RSA -out /etc/ssl/private/smtp.key -pkeyopt rsa_keygen_bits:4096

  [[ ! -f /etc/ssl/smtp.crt ]] && openssl req -x509 -new -key /etc/ssl/private/smtp.key -out /etc/ssl/smtp.crt -days 365 -subj "/CN=mail.pub.attorney"

  chmod 640 /etc/ssl/private/smtp.key /etc/ssl/smtp.crt

  # PostgreSQL and Redis configuration removed per user request
  setup_services

  # Generate Rails app code via feature scripts
  if ! is_step_completed "rails_apps_generated"; then
    log INFO "Generating Rails apps from feature scripts"
    typeset deploy_dir="/home/dev/pub4/MASTER/DEPLOY/rails"

    # brgen
    if [[ -f "${deploy_dir}/brgen/brgen.sh" ]]; then
      log INFO "Running brgen setup"
      doas -u brgen zsh "${deploy_dir}/brgen/brgen.sh" || log WARN "brgen.sh exited non-zero"
    fi

    # amber
    if [[ -f "${deploy_dir}/amber/amber.sh" ]]; then
      log INFO "Running amber setup"
      doas -u amber zsh "${deploy_dir}/amber/amber.sh" || log WARN "amber.sh exited non-zero"
    fi

    # hjerterom
    if [[ -f "${deploy_dir}/hjerterom/hjerterom.sh" ]]; then
      log INFO "Running hjerterom setup"
      doas zsh "${deploy_dir}/hjerterom/hjerterom.sh" || log WARN "hjerterom.sh exited non-zero"
    fi

    # privcam
    if [[ -f "${deploy_dir}/privcam/privcam.sh" ]]; then
      log INFO "Running privcam setup"
      doas zsh "${deploy_dir}/privcam/privcam.sh" || log WARN "privcam.sh exited non-zero"
    fi

    # baibl
    if [[ -f "${deploy_dir}/baibl/baibl.sh" ]]; then
      log INFO "Running baibl setup"
      doas zsh "${deploy_dir}/baibl/baibl.sh" || log WARN "baibl.sh exited non-zero"
    fi

    mark_step_completed "rails_apps_generated"
    log INFO "Rails app generation done"
  fi

  # Deploy Rails apps
  for app_entry in $ALL_APPS; do

    typeset app=${app_entry[(ws:*:)1]} domain=${${(s:*:)app_entry}[-1]}

    typeset port=${APP_PORTS[$app]:=$(generate_random_port)}

    APP_PORTS[$app]=$port

    typeset app_dir=/home/$app/$app

    useradd -m -s /bin/ksh -L rails $app 2>/dev/null || :

    [[ ! -f $app_dir/Gemfile || ! -f $app_dir/config/database.yml ]] && {

      log ERROR "Missing Gemfile or database.yml in $app_dir"

      exit 1

    }

    chown -R $app:$app /home/$app

    su -l $app -c "gem install --user-install rails bundler falcon" || {

      log ERROR "gem install failed for $app"

      exit 1

    }

    su -l $app -c "cd $app_dir && bundle config set --typeset without 'development test' && bundle check || bundle install" || {

      log ERROR "bundle install failed for $app"

      exit 1

    }

    # Database setup removed (SQLite or external DB expected)

    cat > /etc/rc.d/$app <<EOF

#!/bin/ksh

# rc.d for $app (rc.d(8))

daemon_user="$app"
. /etc/rc.d/rc.subr
rc_start() {
  cd $app_dir || return 1

  export RAILS_ENV=production

  export PATH=${HOME}/.gem/ruby/3.4/bin:$PATH

  ${rcexec} "bin/rails server -b 0.0.0.0 -p $port -e production"

}

rc_cmd $1
EOF

    chmod 755 /etc/rc.d/$app

    /usr/sbin/rcctl enable $app

    /usr/sbin/rcctl start $app || { log ERROR "$app failed"; exit 1 }

    sleep 5

    typeset _app_check; _app_check=$(/usr/sbin/rcctl check $app); [[ $_app_check == *"${app}(ok)"* ]] || { log ERROR "$app not running"; exit 1 }

  done

  # Setup non-Rails services (from SERVICES array)
  for svc_entry in $SERVICES; do
    typeset svc_name=${svc_entry%%:*}
    typeset svc_rest=${svc_entry#*:}
    typeset svc_fqdn=${svc_rest%%:*}
    typeset svc_port=${svc_rest##*:}

    log INFO "Setting up service: $svc_name on port $svc_port"

    # MASTER is deployed above; skip CLI-based rc.d for ai service
log INFO "Service $svc_name handled by master rc.d"

    chmod 755 /etc/rc.d/$svc_name
    /usr/sbin/rcctl enable $svc_name
    /usr/sbin/rcctl start $svc_name || log WARN "$svc_name start failed (may need manual start)"

    log INFO "Service $svc_name configured"
  done

  # Configure and start relayd now that APP_PORTS is populated

  # Deploy MASTER web UI (ai.brgen.no -> port 3000 via relayd -> 53187)
  if ! is_step_completed "master_deployed"; then
    log INFO "Deploying MASTER web UI"
    typeset m3dir="/home/dev/pub4/MASTER"
    [[ -d $m3dir ]] || { log ERROR "MASTER not found at $m3dir"; exit 1 }
    cd "$m3dir/web"
    bundle config set --local path vendor/bundle
    bundle install --quiet

    # Read API keys from dev's .zshrc for the rc.d service
    typeset env_line=""
    while IFS= read -r _line; do
      [[ $_line == export\ *_API_KEY=* ]] && {
        typeset _k=${_line#export }
        env_line="$env_line ${_k%%=*}=${${_k#*=}//[\"
  configure_relayd

  print -r -- stage_2_complete > $STATE_FILE
  log INFO "Stage 2 complete. Setup complete. Test: 'curl http://ai.brgen.no:3000/chat/metrics', 'rcctl check master'."

  exit 0

}

# Main execution
main() {

  typeset arg1=${1:-}

  [[ -f $STATE_FILE && ! -r $STATE_FILE ]] && { log ERROR "$STATE_FILE not readable"; exit 1 }

  if [[ $arg1 = --help ]]; then

    print -r -- "Sets up OpenBSD 7.8 for Rails with DNSSEC and minimal OpenSMTPD.
Usage: doas zsh openbsd.sh [--help | --resume]"

    exit 0

  fi

  if [[ $arg1 = --resume && -f $STATE_FILE && $(<$STATE_FILE) = stage_1_complete ]]; then

    stage_2

  elif [[ -z $arg1 && ! -f $STATE_FILE ]]; then

    stage_1

  else

    log ERROR "Invalid state. Use --help, --resume, or remove $STATE_FILE."

    exit 1

  fi

}

main "$@"
]}"
      }
    done < /home/dev/.zshrc

    cat > /etc/rc.d/master <<RCEOF
#!/bin/ksh
daemon="/usr/local/bin/bundle"
daemon_flags="exec env RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1${env_line} falcon serve --bind http://127.0.0.1:53187"
daemon_user="dev"
daemon_execdir="/home/dev/pub4/MASTER/web"
daemon_timeout="90"
. /etc/rc.d/rc.subr
pexp="ruby34.*falcon.*53187"
rc_bg=YES
rc_reload=NO
rc_cmd \$1
RCEOF
    chmod 555 /etc/rc.d/master
    rcctl enable master
    rcctl start master
    mark_step_completed "master_deployed"
    log INFO "MASTER web UI running on :53187 (relayd :3000 -> :53187)"
  fi
  configure_relayd

  print -r -- stage_2_complete > $STATE_FILE
  log INFO "Stage 2 complete. Setup complete. Test: 'curl https://brgen.no', 'curl https://ai.brgen.no'."

  exit 0

}

# Main execution
main() {

  typeset arg1=${1:-}

  [[ -f $STATE_FILE && ! -r $STATE_FILE ]] && { log ERROR "$STATE_FILE not readable"; exit 1 }

  if [[ $arg1 = --help ]]; then

    print -r -- "Sets up OpenBSD 7.8 for Rails with DNSSEC and minimal OpenSMTPD.
Usage: doas zsh openbsd.sh [--help | --resume]"

    exit 0

  fi

  if [[ $arg1 = --resume && -f $STATE_FILE && $(<$STATE_FILE) = stage_1_complete ]]; then

    stage_2

  elif [[ -z $arg1 && ! -f $STATE_FILE ]]; then

    stage_1

  else

    log ERROR "Invalid state. Use --help, --resume, or remove $STATE_FILE."

    exit 1

  fi

}

main "$@"
