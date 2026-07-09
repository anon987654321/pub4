#!/usr/bin/env zsh
# deploy-diff.sh — compare key VPS configs against DEPLOY/openbsd/etc (read-only).
#
# Usage:
#   zsh DEPLOY/openbsd/scripts/deploy-diff.sh
#   SSH_HOST=dev@46.23.89.226 SSH_KEY=~/.ssh/id_ed25519_brgen zsh DEPLOY/openbsd/scripts/deploy-diff.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ETC="${ROOT}/etc"
SSH_HOST=${SSH_HOST:-dev@46.23.89.226}
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
ssh "${SSH_OPTS[@]}" "$SSH_HOST" 'for s in nsd httpd relayd smtpd master brgen amber bsdports hjerterom; do
  /usr/sbin/rcctl check "$s" 2>/dev/null || echo "$s: missing"
done' || echo "SSH failed — install key and flush bruteforce if needed."