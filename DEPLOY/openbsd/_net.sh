#!/usr/bin/env zsh
set -euo pipefail

# DNS, NSD, DNSSEC, and cert utilities.

validate_ip() {
  typeset ip=$1
  [[ $ip =~ '^([0-9]{1,3}\.){3}[0-9]{1,3}$' ]] || return 1
  typeset -a octets; octets=(${(s:.:)ip})
  for octet in $octets; do (( octet > 255 )) && return 1; done
  return 0
}

generate_random_port() {
  log ERROR "missing APP_PORTS entry; assign a fixed port in openbsd.sh"
  exit 1
}

cleanup_nsd() {
  log INFO "Cleaning nsd(8)"
  [[ -d /var/nsd ]] || { log ERROR "/var/nsd missing"; exit 1 }
  /usr/bin/timeout 5 /usr/sbin/rcctl stop nsd || log WARN "/usr/sbin/rcctl stop nsd failed"
  /usr/bin/timeout 5 zap -f nsd || log WARN "zap -f nsd failed"
  sleep 2
  typeset _out; _out=$(/usr/bin/netstat -an -p udp)
  [[ $_out == *"$BRGEN_IP.53"* ]] && { log ERROR "Port 53 in use"; exit 1 }
  log INFO "Port 53 free"
}

verify_nsd() {
  log INFO "Verifying nsd(8) for all domains"
  for domain in ${ALL_DOMAINS[*]%%:*}; do
    typeset dig_a=${$(/usr/bin/dig @"$BRGEN_IP" "$domain" A +short):-}
    [[ -z $dig_a || $dig_a != $BRGEN_IP ]] && {
      log WARN "nsd(8) A record missing or wrong for $domain (got: ${dig_a:-empty})"
      continue
    }
    typeset dig_dnskey=${$(/usr/bin/dig @"$BRGEN_IP" "$domain" DNSKEY +short):-}
    [[ -z $dig_dnskey ]] && { log WARN "DNSSEC not enabled for $domain"; continue }
  done
  log INFO "nsd(8) verification complete"
}

check_dns_propagation() {
  log INFO "Checking DNS propagation"
  for resolver in $PUBLIC_RESOLVERS; do
    typeset _soa; _soa=$(/usr/bin/dig @$resolver brgen.no SOA +short)
    [[ $_soa == *"ns.brgen.no."* ]] && { log INFO "DNS propagation verified via $resolver"; return 0 }
  done
  log ERROR "DNS propagation incomplete. Check glue records."
  exit 1
}

generate_tlsa_record() {
  typeset domain=$1
  typeset cert=/etc/ssl/$domain.fullchain.pem
  typeset zonefile=/var/nsd/zones/master/$domain.zone
  [[ ! -f $cert ]] && { log WARN "Certificate for $domain not found"; return 1 }
  typeset _raw; _raw=$(openssl x509 -noout -pubkey -in "$cert" | openssl pkey -pubin -outform der 2>/dev/null | openssl dgst -sha256 2>/dev/null)
  typeset tlsa_record=${${(z)_raw}[2]:-}
  (( ! $#tlsa_record )) && { log ERROR "TLSA generation failed for $domain"; exit 1 }
  print -r -- "_443._tcp.$domain. IN TLSA 3 1 1 $tlsa_record" >> "$zonefile"
  sign_zone "$domain"
  log INFO "TLSA updated for $domain"
}

sign_zone() {
  typeset domain=$1
  typeset zonefile=/var/nsd/zones/master/$domain.zone
  typeset signed_zonefile=/var/nsd/zones/master/$domain.zone.signed
  typeset zsk=/var/nsd/zones/master/K$domain.+013+zsk.key
  typeset ksk=/var/nsd/zones/master/K$domain.+013+ksk.key
  [[ -f $zsk && -f $ksk ]] || { log ERROR "ZSK or KSK missing for $domain"; exit 1 }
  ldns-signzone -n -p -s $(dd if=/dev/random bs=16 count=1 2>/dev/null | sha1 -q) "$zonefile" "$zsk" "$ksk"
  nsd-checkzone "$domain" "$signed_zonefile" || { log ERROR "Signed zone invalid for $domain"; exit 1 }
  nsd-control reload
}

retry_failed_certs() {
  log INFO "Retrying failed certificates"
  for domain in ${(k)FAILED_CERTS}; do
    typeset dns_check=${$(/usr/bin/dig @"$BRGEN_IP" "$domain" A +short):-}
    [[ $dns_check != $BRGEN_IP ]] && { log WARN "DNS for $domain failed"; continue }
    print -r -- "retry_$domain" > "/var/www/acme/retry_$domain"
    typeset http_status=${$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $domain" "http://$BRGEN_IP/.well-known/acme-challenge/retry_$domain"):-000}
    rm -f "/var/www/acme/retry_$domain"
    [[ $http_status != 200 ]] && { log WARN "HTTP test for $domain failed"; continue }
    if acme-client -v -f /etc/acme-client.conf "$domain"; then
      unset FAILED_CERTS[$domain]
      generate_tlsa_record "$domain"
    else
      log WARN "Retry failed for $domain"
    fi
  done
}
