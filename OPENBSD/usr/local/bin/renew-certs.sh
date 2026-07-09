#!/usr/bin/env zsh
# Renew TLS certs via acme-client; relayd reload only.
# Zone signing and TLSA records: usr/local/bin/nsd-resign (daily.local).
set -euo pipefail

ALL_DOMAINS=(
  brgen.no longyearbyn.no oshlo.no stvanger.no trmso.no trndheim.no
  reykjavk.is kbenhvn.dk gtebrg.se mlmoe.se stholm.se hlsinki.fi
  brmingham.uk cardff.uk edinbrgh.uk glasgw.uk lndon.uk lverpool.uk
  mnchester.uk amstrdam.nl rottrdam.nl utrcht.nl brssels.be zrich.ch
  lchtenstein.li frankfrt.de brdeaux.fr mrseille.fr mlan.it lisbon.pt
  wrsawa.pl gdnsk.pl austn.us chcago.us denvr.us dllas.us dnver.us
  dtroit.us houstn.us lsangeles.com mnnesota.com newyrk.us prtland.com
  wshingtondc.com pub.healthcare pub.attorney freehelp.legal
  bsdports.org bsddocs.org discordb.org
  stacyspassion.com
  foball.no amber.brgen.no
)

for domain in $ALL_DOMAINS; do
  if acme-client -v -f /etc/acme-client.conf "$domain"; then
    print -r -- "Renewed: $domain"
  fi
done

/usr/sbin/rcctl reload relayd