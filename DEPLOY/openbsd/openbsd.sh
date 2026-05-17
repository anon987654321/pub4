#!/usr/bin/env zsh
# Configure OpenBSD 7.8: NSD/DNSSEC, acme-client, Rails, pf, relayd, smtpd.
# Usage: doas zsh openbsd.sh [--help | --resume]
# VERIFIED AGAINST: OpenBSD 7.8 manual pages (2026-01-06)

set -euo pipefail
setopt no_unset nullglob local_traps
zmodload zsh/regex

typeset -a TMPFILES
SCRIPT_DIR=${0:a:h}

source "${SCRIPT_DIR}/_lib.sh"
source "${SCRIPT_DIR}/_net.sh"
source "${SCRIPT_DIR}/_stage1.sh"
source "${SCRIPT_DIR}/_stage2.sh"

trap 'cleanup' EXIT
trap 'error_handler $? $LINENO' ERR INT TERM

# Constants
typeset -r BRGEN_IP="185.52.176.18"
typeset -r HYP_IP="194.63.248.53"
typeset -r LOCALHOST="127.0.0.1"
typeset -r EMAIL_ADDRESS="bergen@pub.attorney"
typeset -r STATE_FILE="./openbsd_setup_state"

typeset -a PUBLIC_RESOLVERS=(8.8.8.8 1.1.1.1 9.9.9.9)
typeset -A APP_PORTS
typeset -A FAILED_CERTS

validate_ip "$BRGEN_IP" || { log ERROR "Invalid BRGEN_IP: $BRGEN_IP"; exit 1 }
validate_ip "$HYP_IP"   || { log ERROR "Invalid HYP_IP: $HYP_IP"; exit 1 }

ALL_APPS=(
  brgen:brgen.no
  amber:amber.brgen.no
  bsdports:bsdports.org
  baibl:baibl.no
)

SERVICES=()

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

_openbsd_sh() {
  _arguments '--help[Show usage information]' '--resume[Resume with Stage 2]'
}

main() {
  typeset arg1=${1:-}
  [[ -f $STATE_FILE && ! -r $STATE_FILE ]] && { log ERROR "$STATE_FILE not readable"; exit 1 }

  if [[ $arg1 = --help ]]; then
    print -r -- "Configure OpenBSD 7.8 for Rails with DNSSEC and relayd TLS+SNI.
Usage: doas zsh openbsd.sh [--help | --resume]"
    exit 0
  elif [[ $arg1 = --resume && -f $STATE_FILE && $(<$STATE_FILE) = stage_1_complete ]]; then
    stage_2
  elif [[ -z $arg1 && ! -f $STATE_FILE ]]; then
    stage_1
  else
    log ERROR "Invalid state. Use --help, --resume, or remove $STATE_FILE."
    exit 1
  fi
}

main "$@"
