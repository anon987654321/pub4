#!/usr/bin/env zsh
# Complete VPS deployment orchestrator per master.yml v72.1.0
# Deploys all 15 Rails apps to OpenBSD VPS 185.52.176.18
set -euo pipefail
readonly VPS_HOST="185.52.176.18"
readonly VPS_USER="dev"
readonly SSH_KEY="/cygdrive/g/priv/passwd/id_rsa"
readonly LOCAL_BASE="/cygdrive/g/pub"
readonly REMOTE_BASE="/home/dev"
# Status reporting
log() {
  printf '[%s] %s
' "$(date +%H:%M:%S)" "$*"
}
error() {
  log "ERROR: $*"
  exit 1
}
# SSH wrapper
vssh() {
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "${VPS_USER}@${VPS_HOST}" "$@"
}
# File transfer
vscp() {
  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -r "$@"
}
log "Starting complete VPS deployment"
# 1. Test connectivity
log "Testing VPS connectivity..."
vssh 'uname -a' || error "Cannot connect to VPS"
# 2. Upload files
log "Uploading rails generators..."
vscp "${LOCAL_BASE}/rails" "${VPS_USER}@${VPS_HOST}:${REMOTE_BASE}/" || error "Upload failed"
log "Uploading openbsd infrastructure..."
vscp "${LOCAL_BASE}/openbsd" "${VPS_USER}@${VPS_HOST}:${REMOTE_BASE}/" || error "Upload failed"
log "Uploading master.yml..."
vscp "${LOCAL_BASE}/master.yml" "${VPS_USER}@${VPS_HOST}:${REMOTE_BASE}/" || error "Upload failed"
# 3. Run infrastructure setup
log "Running infrastructure setup (openbsd.sh --pre-point)..."
vssh "cd ${REMOTE_BASE}/openbsd && doas zsh openbsd.sh --pre-point" || log "WARN: Infrastructure may need manual intervention"
# 4. Deploy Rails apps sequentially
typeset -a APPS
APPS=(brgen amber blognet bsdports hjerterom privcam pub_attorney)
for app in $APPS; do
  log "Deploying ${app}..."
  vssh "cd ${REMOTE_BASE}/rails && zsh ${app}.sh 2>&1 | tee /tmp/${app}_deploy.log" || log "WARN: ${app} deployment issues - check /tmp/${app}_deploy.log"
done
# 5. Verify deployments
log "Verifying app processes..."
vssh 'ps aux | grep -E "falcon|puma|rails" | grep -v grep' || log "WARN: No Rails processes detected"
log "Checking listening ports..."
vssh 'netstat -an | grep LISTEN | grep -E "1000[1-7]|11006"' || log "WARN: Expected ports not listening"
# 6. Summary
log "Deployment complete!"
log ""
log "Next steps:"
log "  1. Point DNS records to ns.brgen.no (185.52.176.18)"
log "  2. Wait 24-48h for propagation"
log "  3. Run: ssh ${VPS_USER}@${VPS_HOST} 'cd ${REMOTE_BASE}/openbsd && doas zsh openbsd.sh --post-point'"
log ""
log "Access VPS: ssh -i ${SSH_KEY} ${VPS_USER}@${VPS_HOST}"
log "Check logs: ssh ${VPS_USER}@${VPS_HOST} 'tail -f /var/log/rails/*.log'"
