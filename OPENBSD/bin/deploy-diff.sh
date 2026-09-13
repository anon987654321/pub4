#!/usr/bin/env zsh
# deploy-diff.sh — how vm23 differs from OPENBSD/, read-only, from a workstation.
#
# Usage:
#   zsh OPENBSD/bin/deploy-diff.sh
#   SSH_HOST=dev@brgen.no SSH_KEY=~/.ssh/id_ed25519_brgen zsh OPENBSD/bin/deploy-diff.sh
#
# A wrapper over config_drift_gate.rb --remote, which byte-compares every
# verbatim-installed /etc and /usr/local/bin file and root's crontab in one ssh
# session. This adds only what that gate excludes on purpose: a readable diff of
# relayd.conf, which is installed by hand after `relayd -n` rather than verbatim,
# and rcctl's view of the services. sync.rb is the tool that pulls the live side
# back into the repo; this changes nothing in either direction.
#
# SSH_HOST here is login@host in one string, which is how config_drift_gate.rb
# reads it too. OPENBSD/lib/ssh_vm23.sh gives the same name the opposite meaning
# — host alone, with SSH_USER beside it — so never export one for the other.

set -euo pipefail

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  print "usage: zsh OPENBSD/bin/deploy-diff.sh   (SSH_HOST=login@host SSH_KEY=path)"
  exit 0
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export SSH_HOST=${SSH_HOST:-dev@brgen.no}
export SSH_KEY=${SSH_KEY:-~/.ssh/id_ed25519_brgen}
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -i "$SSH_KEY")
drift=0

print "deploy-diff: ${SSH_HOST}"
print "=== verbatim configs and root crontab (config_drift_gate --remote) ==="
ruby "${ROOT}/OPENBSD/config_drift_gate.rb" --remote || drift=1

print "\n=== relayd.conf (excluded from the gate; diffed here) ==="
diff -u "${ROOT}/OPENBSD/etc/relayd.conf" <(ssh "${SSH_OPTS[@]}" "$SSH_HOST" "cat /etc/relayd.conf") || drift=1

print "\n=== rcctl check (remote) ==="
ssh "${SSH_OPTS[@]}" "$SSH_HOST" 'for s in nsd httpd relayd smtpd master brgen amber bsdports; do
  /usr/sbin/rcctl check "$s" 2>/dev/null || echo "$s: missing"
done' || print "SSH failed — install key and flush bruteforce if needed."

exit $drift
