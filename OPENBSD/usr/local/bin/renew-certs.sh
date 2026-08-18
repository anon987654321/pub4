#!/usr/bin/env zsh
# Renew TLS certs via acme-client; relayd reload only.
# Zone signing and TLSA records: usr/local/bin/nsd-resign (daily.local).
set -euo pipefail

ACME_CONF=/etc/acme-client.conf

# Renew what we hold, not what we hope for.
#
# This was a hardcoded list of all 53 domains in acme-client.conf. Only nine of
# them have ever been issued a certificate; the other 44 are NXDOMAIN at their
# registrar, so every weekly run asked Let's Encrypt to validate 44 hostnames
# that do not resolve. That never actually happened, because the script's
# `#!/usr/bin/env zsh` shebang could not find zsh under cron's PATH and the job
# had never once run (see etc/crontab.vm23). Fixing the PATH armed it: the next
# Monday would have been the first real run, and it would have spent 44 failed
# authorizations against the account rate limit to renew nine certificates.
#
# The list is now an intersection of two facts on disk, both of which acme-client
# itself maintains:
#
#   /etc/ssl/<name>.crt        we hold a certificate for this name, and it is the
#                              exact file relayd loads
#   domain "<name>" { ... }    acme-client knows how to renew it
#
# Held-but-unconfigured names are excluded rather than attempted. There is one,
# ai.brgen.no, which is a SAN of brgen.no rather than a domain acme-client knows
# how to renew on its own — passing it in fails on a config lookup before a
# single packet leaves the box. Renewal covers exactly what is deployed, and
# first issuance stays a deliberate act.
typeset -a CONFIGURED HELD DOMAINS

CONFIGURED=()
while IFS= read -r line; do
  [[ $line == domain\ \"*\"* ]] || continue
  line=${line#domain \"}
  CONFIGURED+=(${line%%\"*})
done < $ACME_CONF

# (N) nullglob, :t basename, :r strip the final extension -- "amber.brgen.no.crt"
# becomes "amber.brgen.no". smtp.crt is smtpd's own self-signed certificate and
# is not ACME's to renew; cert.pem is the trust store.
HELD=(/etc/ssl/*.crt(N:t:r))
HELD=(${HELD:#smtp})

DOMAINS=(${HELD:*CONFIGURED})

if (( ${#DOMAINS} == 0 )); then
  print -ru2 -- "renew-certs: no held certificate matches a domain in $ACME_CONF — refusing to run"
  exit 1
fi

typeset -a skipped
skipped=(${HELD:|DOMAINS})
(( ${#skipped} )) && print -r -- "renew-certs: held but not in $ACME_CONF, skipping: ${skipped}"

# http-01 needs a listener on port 80, and relayd is not it: relayd.conf declares
# exactly one relay, `listen on 0.0.0.0 port 443 tls`. httpd serves /var/www/acme
# and nothing else. It was down on 2026-08-12 -- daily.out had been saying so under
# "Services that should be running but aren't" -- and the only visible symptom was
# bsdports.org failing to renew with 7 days left on its certificate while the other
# eight succeeded, because their authorizations were still cached at Let's Encrypt
# and did not need a challenge. Cached authorizations expire; this is the renewal
# that quietly stops working months before anyone notices.
if ! /usr/sbin/rcctl check httpd >/dev/null 2>&1; then
  print -ru2 -- "renew-certs: httpd is down — starting it, http-01 challenges need port 80"
  /usr/sbin/rcctl start httpd || print -ru2 -- "renew-certs: httpd would not start; renewals needing a challenge will fail"
fi

print -r -- "renew-certs: renewing ${#DOMAINS} of ${#HELD} held certificate(s): ${DOMAINS}"

# acme-client exits 0 whether it renewed or found the certificate still valid, so
# counting successful invocations counts every domain every week — which meant
# the relayd restart below fired on every run. That is not free: relayd's health
# check is `interval 120`, and after a restart brgen's table sits empty until the
# first check passes. Measured 2026-08-12, that is roughly 20 seconds of 000 on
# brgen.no and every city with it, once a week, for nothing.
#
# The file mtime is the honest signal: acme-client rewrites the fullchain only
# when it actually issues.
typeset renewed=0
for domain in $DOMAINS; do
  typeset chain=/etc/ssl/$domain.fullchain.pem
  typeset before=0
  [[ -f $chain ]] && before=$(stat -f %m $chain)

  if acme-client -v -f $ACME_CONF "$domain"; then
    typeset after=0
    [[ -f $chain ]] && after=$(stat -f %m $chain)
    if (( after > before )); then
      print -r -- "Renewed: $domain"
      (( renewed += 1 ))
    fi
  fi
done

print -r -- "renew-certs: $renewed renewed of ${#DOMAINS}"

# restart, not reload. `rcctl reload relayd` sends SIGHUP, and relayd loads its
# tls keypairs in the parent before chroot -- a SIGHUP after the certificate files
# have been replaced leaves it accepting connections on 443 and answering none of
# them. Measured 2026-08-12: seven certificates renewed, one reload, and every host
# on the box returned curl (52) Empty reply from server until relayd was restarted.
# rcctl check reported relayd(ok) throughout, so nothing on the box disagreed.
#
# Only when something changed. A restart is a real interruption, and the common
# case is that nothing was renewed at all.
if (( renewed > 0 )); then
  print -r -- "renew-certs: restarting relayd to load $renewed replaced certificate(s)"
  /usr/sbin/rcctl restart relayd
else
  print -r -- "renew-certs: nothing renewed, leaving relayd alone"
fi
