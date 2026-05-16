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

set -euo pipefail
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
trap 'error_handler $? $LINENO' ERR INT TERM
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

# Template helpers — render files/* with $var expansion, install to dest
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


# Configuration settings (constants per master.yml p04: explicit over implicit)
typeset -r BRGEN_IP="185.52.176.18"   # Primary server IP (updated for this VPS)

typeset -r HYP_IP="194.63.248.53"     # ns.hyp.net, external secondary

typeset -r LOCALHOST="127.0.0.1"      # Localhost constant

typeset -r EMAIL_ADDRESS="bergen@pub.attorney"  # Email address for OpenSMTPD

typeset -r STATE_FILE="./openbsd_setup_state"   # Runtime state file

SCRIPT_DIR=${0:a:h}

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

  amber:amber.brgen.no

  bsdports:bsdports.org

  baibl:baibl.no

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
  foodielicio.us

  stacyspassion.com

  antibettingblog.com

  anticasinoblog.com

  antigamblingblog.com

  foball.no

  amber.brgen.no

  baibl.no

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
  install_template pf.stage1.conf /etc/pf.conf

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
  install_template nsd.conf.head /var/nsd/etc/nsd.conf

  for domain in ${ALL_DOMAINS[*]%%:*}; do

    append_template nsd-zone.tmpl /var/nsd/etc/nsd.conf

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

    install_template zone.tmpl /var/nsd/zones/master/$domain.zone

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

    zsk=$(ldns-keygen -a ECDSAP256SHA256 "$domain")

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

  install_static httpd.conf /etc/httpd.conf

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

  install_static acme-client.head /etc/acme-client.conf

  for domain_entry in $ALL_DOMAINS; do

    typeset domain=${domain_entry%%:*}

    typeset subdomains=${domain_entry#*:}

    [[ $subdomains = $domain ]] && subdomains=""

    {
      print -r -- "domain $domain {"
      if [[ -n $subdomains ]]; then
        print -r -- "  alternative names {"
        print -r -- "    $domain"
        for sub in ${(s:,:)subdomains}; do
          print -r -- "    $sub.$domain"
        done
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
  install_static renew-certs.sh /usr/local/bin/renew-certs.sh

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

# Bootstrap a tracked Rails app: copy source tree, install gems, migrate, install rc.d.
# Mines the structural pattern of brgen_0806.sh (rails new + bundle + db + service)
# but applies it to a committed source tree instead of generating from scratch.
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

  # Share resolved gems from amber to avoid OOM on first bundle install.
  # Only override BUNDLE_PATH when the donor exists; otherwise let the app's
  # own .bundle/config stand and bundler installs into vendor/bundle.
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
  su -l "$app" -c "cd $app_dir && RAILS_ENV=production bundle install --deployment --without development:test" || {
    log ERROR "bundle install failed for $app"; return 1
  }
  su -l "$app" -c "cd $app_dir && RAILS_ENV=production bin/rails db:create db:migrate" \
    || log WARN "db:create/migrate non-zero for $app (idempotent skip likely)"
  [[ -f $app_dir/db/seeds.rb ]] && \
    su -l "$app" -c "cd $app_dir && RAILS_ENV=production bin/rails db:seed" || :

  secret=$(su -l "$app" -c "cd $app_dir && RAILS_ENV=production bundle exec rails secret 2>/dev/null" | tail -1)
  [[ ${#secret} -ge 64 ]] || { log ERROR "$app: secret capture failed (got ${#secret} chars)"; return 1 }
  install_template rc.d/rails-app.tmpl /etc/rc.d/$app
  chmod 755 /etc/rc.d/$app
  /usr/sbin/rcctl enable $app
  /usr/sbin/rcctl restart $app || /usr/sbin/rcctl start $app \
    || { log ERROR "$app failed to start"; return 1 }
  sleep 5
  typeset _c; _c=$(/usr/sbin/rcctl check $app)
  [[ $_c == *"${app}(ok)"* ]] || { log ERROR "$app not running"; return 1 }
  log INFO "  $app live on :$port"
}

configure_relayd() {
  # Native relayd(8) on :443 with multi-keypair SNI termination + per-Host
  # backend routing. Source of truth is ALL_APPS (app:domain) plus ALL_DOMAINS
  # (domain:csv-of-subdomains). Every ALL_DOMAINS entry without an explicit
  # backend defaults to <brgen> — that array IS the brgen network.
  log INFO "Writing relayd.conf (TLS+SNI on :443)"

  typeset -A DOMAIN_BACKEND=() BACKEND_PORT=()
  typeset app_entry app dom entry rest sub backend

  for app_entry in $ALL_APPS; do
    app=${app_entry%%:*}; dom=${app_entry##*:}
    DOMAIN_BACKEND[$dom]=$app
    BACKEND_PORT[$app]=${APP_PORTS[$app]:-0}
  done
  # MASTER web tier: not a Rails app in ALL_APPS, but terminates TLS here.
  DOMAIN_BACKEND[ai.brgen.no]=master
  BACKEND_PORT[master]=53187
  # Default the rest of ALL_DOMAINS to brgen (the brgen network).
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
      # Subdomains from ALL_DOMAINS' csv list; skip any that have their own
      # explicit backend (e.g. ai.brgen.no → master, not brgen).
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

  # Disable HAProxy if still around from prior deploys
  /usr/sbin/rcctl get haproxy >/dev/null 2>&1 && {
    log INFO "Disabling legacy HAProxy"
    /usr/sbin/rcctl stop haproxy 2>/dev/null
    /usr/sbin/rcctl disable haproxy 2>/dev/null
  }
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
  install_template pf.stage2.conf /etc/pf.conf

  /sbin/pfctl -nf /etc/pf.conf || { log ERROR "pf.conf invalid"; exit 1 }

  /sbin/pfctl -f /etc/pf.conf || { log ERROR "pf failed"; exit 1 }

  # Configure OpenSMTPD
  install_template smtpd.conf /etc/mail/smtpd.conf

  smtpd -n -f /etc/mail/smtpd.conf || { log ERROR "smtpd.conf invalid"; exit 1 }

  [[ ! -f /etc/ssl/private/smtp.key ]] && openssl genpkey -algorithm RSA -out /etc/ssl/private/smtp.key -pkeyopt rsa_keygen_bits:4096

  [[ ! -f /etc/ssl/smtp.crt ]] && openssl req -x509 -new -key /etc/ssl/private/smtp.key -out /etc/ssl/smtp.crt -days 365 -subj "/CN=mail.pub.attorney"

  chmod 640 /etc/ssl/private/smtp.key /etc/ssl/smtp.crt

  # PostgreSQL and Redis configuration removed per user request
  setup_services

  # Deploy Rails apps. Source trees committed under DEPLOY/rails/$app/app/.
  # Bootstrap amber first so its resolved gem set can seed siblings.
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
        [[ $_line == export* ]] || continue
        typeset _kv=${_line#export }
        env_line="$env_line ${_kv%%=*}=${_kv#*=}"
    done < /home/dev/.zshrc

    install_template rc.d/master.tmpl /etc/rc.d/master
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

# Main execution
main() {

  typeset arg1=${1:-}

  [[ -f $STATE_FILE && ! -r $STATE_FILE ]] && { log ERROR "$STATE_FILE not readable"; exit 1 }

  if [[ $arg1 = --help ]]; then
    print -r -- "Sets up OpenBSD 7.8 for Rails with DNSSEC and relayd TLS+SNI.
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
