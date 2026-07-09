#!/usr/bin/env zsh
set -euo pipefail

readonly VPS_IP="46.23.89.226"
readonly VPS_USER="dev"

cd ~/pub4
git add -A
git commit -m "deploy $(date +%Y-%m-%d_%H:%M:%S)" || true
git push origin main

ssh -o StrictHostKeyChecking=no ${VPS_USER}@${VPS_IP} << 'ENDSSH'
set -euo pipefail
cd ~/pub4
git pull origin main
cd DEPLOY/openbsd
doas zsh DEPLOY.sh
ENDSSH
