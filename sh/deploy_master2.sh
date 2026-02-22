#!/usr/bin/env zsh
# Deploy MASTER2 to OpenBSD VPS
# Usage: zsh sh/deploy_master2.sh [user@host]
set -euo pipefail

readonly VPS="${1:-dev@185.52.176.18}"
readonly REPO="https://github.com/anon987654321/pub4.git"
readonly REMOTE_DIR="/home/${VPS##*@}/pub4"

print "==> MASTER2 deploy → ${VPS}"
print "    repo:   ${REPO}"
print "    target: ${REMOTE_DIR}/MASTER2"
print ""

# 1. Push latest
print "--- pushing local commits ---"
cd "$(git rev-parse --show-toplevel)"
git push origin main
print "ok"

# 2. Bootstrap on VPS
print "--- running bootstrap on VPS ---"
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 "${VPS}" /bin/sh << ENDSSH
set -e
export PATH="\$PATH:/usr/local/bin"

# Clone or pull
if [ -d "${REMOTE_DIR}/.git" ]; then
  echo "pulling latest..."
  cd "${REMOTE_DIR}" && git pull --ff-only origin main
else
  echo "cloning..."
  git clone "${REPO}" "${REMOTE_DIR}"
  cd "${REMOTE_DIR}"
fi

cd "${REMOTE_DIR}/MASTER2"

# Install system deps if missing (OpenBSD)
if command -v pkg_add >/dev/null 2>&1; then
  echo "checking system packages..."
  for pkg in ruby-3.3.8 ruby33-bundler git libxml2 libxslt; do
    pkg_add -I "\${pkg}" 2>/dev/null && echo "  installed \${pkg}" || true
  done
fi

# Ruby/bundler paths on OpenBSD
export GEM_HOME="\${HOME}/.gem/ruby/3.3"
export PATH="\${GEM_HOME}/bin:\${PATH}"

# Install gems
echo "bundle install..."
bundle install --quiet

# Create .env if missing
if [ ! -f .env ]; then
  cp .env.example .env
  echo ""
  echo "!!! ACTION REQUIRED !!!"
  echo "Edit ${REMOTE_DIR}/MASTER2/.env and set OPENROUTER_API_KEY, then re-run."
  echo ""
fi

# Preflight check
echo "--- preflight ---"
zsh scripts/openbsd_preflight.zsh || true

echo ""
echo "==> MASTER2 is ready."
echo "    To start:  cd ${REMOTE_DIR}/MASTER2 && bin/master"
echo "    As daemon: bin/master --daemon"
ENDSSH

print ""
print "==> done. Connect and run:"
print "    ssh ${VPS}"
print "    cd ${REMOTE_DIR}/MASTER2"
print "    bin/master"
