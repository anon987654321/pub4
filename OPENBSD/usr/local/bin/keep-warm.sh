#!/bin/ksh
# Keep the public apps' pages resident, so a visitor is never the one paying for
# the page-in.
#
# The box carries more than fits: measured 2026-08-17 at 918M real with 43M free
# and swap 91% used, paging continuously at rest. OpenBSD evicts whatever is
# idle, which on a low-traffic site is everything between visits — so the first
# request after a quiet spell reads its own working set back from disk. amber's
# home measured 12.19s to first byte cold against 0.40s warm. Nearly every real
# visitor is the cold case.
#
# One request every ten minutes is enough to keep a working set warm and is
# invisible as load: two page renders per ten minutes against a box that idles at
# 84%.
#
# Install: doas cp OPENBSD/usr/local/bin/keep-warm.sh /usr/local/bin/ &&
#          doas chmod 755 /usr/local/bin/keep-warm.sh
# Cron (root): */10 * * * * /usr/local/bin/keep-warm.sh >> /var/log/keep-warm.log 2>&1

set -e
export PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin

# Loopback and a Host header rather than the public name: this is about keeping
# the Ruby process resident, and going out through relayd and back would measure
# the network as well as pay for TLS on a box that has no spare core.
#
# brgen and amber only. bsdports and master are resource_guard's OPTIONAL set —
# warming what another job exists to shed is how two jobs fight over one box, and
# master is 927M of address space that is correctly swapped out until someone
# actually opens the face.
set -A TARGETS "brgen.no 38182" "amber.brgen.no 61352"

# A real page, not /up. The health endpoint answers from a handful of objects and
# leaves the render path — views, the feed query, the template cache — exactly as
# cold as it found it, which is the part a visitor waits for.
for target in "${TARGETS[@]}"; do
  set -- $target
  host=$1
  port=$2
  # Skip a target that is not listening: resource_guard sheds amber under real
  # pressure, and warming it back up would undo that deliberately.
  nc -z 127.0.0.1 "$port" 2>/dev/null || continue

  start=$(date +%s)
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 45 \
         -H "Host: $host" "http://127.0.0.1:$port/" 2>/dev/null || echo 000)
  elapsed=$(( $(date +%s) - start ))
  # Only worth a log line when it was slow or it failed — a warm hit every ten
  # minutes for a month is 4,000 lines saying nothing.
  if [ "$code" != "200" ] || [ "$elapsed" -ge 3 ]; then
    echo "$(date '+%Y-%m-%dT%H:%M:%S') $host $code in ${elapsed}s"
  fi
done
