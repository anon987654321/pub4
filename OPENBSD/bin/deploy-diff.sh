#!/usr/bin/env zsh
# deploy-diff.sh — compare key VPS configs against OPENBSD/etc (read-only).
#
# Usage:
#   zsh OPENBSD/bin/deploy-diff.sh
#   SSH_HOST=dev@brgen.no SSH_KEY=~/.ssh/id_ed25519_brgen zsh OPENBSD/bin/deploy-diff.sh
#
# SSH_HOST here is login@host in one string, which is how config_drift_gate.rb
# reads it too. OPENBSD/lib/ssh_vm23.sh gives the same name the opposite meaning
# — host alone, with SSH_USER beside it — so never export one for the other.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REPO_ETC="${ROOT}/OPENBSD/etc"
SSH_HOST=${SSH_HOST:-dev@brgen.no}
SSH_KEY=${SSH_KEY:-~/.ssh/id_ed25519_brgen}
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=10 -i "$SSH_KEY")

FILES=(
  pf.conf
  relayd.conf
  master.env.sample
)

echo "deploy-diff: ${SSH_HOST}"
echo "repo: ${REPO_ETC}"
echo

for f in "${FILES[@]}"; do
  local_repo="${REPO_ETC}/${f}"
  remote="/etc/${f}"
  [[ -f $local_repo ]] || { echo "skip (no repo file): $f"; continue }
  echo "=== $f ==="
  if ssh "${SSH_OPTS[@]}" "$SSH_HOST" "test -f $remote"; then
    diff -u "$local_repo" <(ssh "${SSH_OPTS[@]}" "$SSH_HOST" "cat $remote") || true
  else
    echo "remote missing: $remote"
    echo "(repo excerpt)"
    head -20 "$local_repo"
  fi
  echo
done

echo "rcctl check (remote):"
ssh "${SSH_OPTS[@]}" "$SSH_HOST" 'for s in nsd httpd relayd smtpd master brgen amber bsdports; do
  /usr/sbin/rcctl check "$s" 2>/dev/null || echo "$s: missing"
done' || echo "SSH failed — install key and flush bruteforce if needed."
