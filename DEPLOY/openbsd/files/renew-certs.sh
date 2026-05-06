#!/bin/ksh
# Certificate renewal script
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
  typeset -a lines
  lines=("${(@f)$(<$zonefile)}")
  lines=("${(@)lines:#_443._tcp.$domain. IN TLSA*}")
  print -rl -- $lines > "$zonefile"
  print -r -- "_443._tcp.$domain. IN TLSA 3 1 1 $tlsa_record" >> "$zonefile"
  ldns-signzone -n -p -s $(dd if=/dev/random bs=16 count=1 2>/dev/null | sha1 -q) "$zonefile" "$zsk" "$ksk"
  nsd-control reload
}

ALL_DOMAINS=(
  brgen.no longyearbyn.no oshlo.no stvanger.no trmso.no trndheim.no
  reykjavk.is kbenhvn.dk gtebrg.se mlmoe.se stholm.se hlsinki.fi
  brmingham.uk cardff.uk edinbrgh.uk glasgw.uk lndon.uk lverpool.uk
  mnchester.uk amstrdam.nl rottrdam.nl utrcht.nl brssels.be zrich.ch
  lchtenstein.li frankfrt.de brdeaux.fr mrseille.fr mlan.it lisbon.pt
  wrsawa.pl gdnsk.pl austn.us chcago.us denvr.us dllas.us dnver.us
  dtroit.us houstn.us lsangeles.com mnnesota.com newyrk.us prtland.com
  wshingtondc.com pub.healthcare pub.attorney freehelp.legal
  bsdports.org bsddocs.org discordb.org foodielicio.us
  stacyspassion.com antibettingblog.com anticasinoblog.com
  antigamblingblog.com foball.no
)

for domain in ${ALL_DOMAINS[@]}; do
  if acme-client -v -f /etc/acme-client.conf "$domain"; then
    echo "Renewed: $domain"
    generate_tlsa_record "$domain"
  fi
done

/usr/sbin/rcctl reload relayd
