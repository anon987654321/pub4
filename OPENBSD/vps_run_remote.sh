#!/usr/bin/env zsh
# Workstation helper: copy vps_install_all.sh to VM via hypervisor jump and run it.
set -euo pipefail

SCRIPT_DIR=${0:a:h}
INSTALL_SH=${SCRIPT_DIR}/vps_install_all.sh
KEY=${SSH_KEY:-${HOME}/.ssh/id_ed25519_brgen}
HYP=${HYPERVISOR:-dev@server4.openbsd.amsterdam}
HYP_PORT=${HYP_PORT:-31415}
VM=${VM_HOST:-dev@46.23.89.226}
REMOTE_LOG=/tmp/pub4_install_latest.log

log() { printf '[vps_run] %s\n' "$*" }

[[ -f $INSTALL_SH ]] || { log "missing $INSTALL_SH"; exit 1 }

log "upload install script"
scp -i "$KEY" -P "$HYP_PORT" -o StrictHostKeyChecking=accept-new "$INSTALL_SH" "${HYP}:/tmp/vps_install_all.sh"

log "start install on VM (nohup — may take 30–60 min on 1GB RAM)"
ssh -i "$KEY" -p "$HYP_PORT" -o StrictHostKeyChecking=accept-new "$HYP" \
  "scp -o StrictHostKeyChecking=accept-new /tmp/vps_install_all.sh ${VM}:/tmp/vps_install_all.sh && \
   ssh -o StrictHostKeyChecking=accept-new ${VM} 'chmod +x /tmp/vps_install_all.sh; nohup /tmp/vps_install_all.sh > ${REMOTE_LOG} 2>&1 & echo PID:\$!'"

log "tail log: ssh jump → ssh ${VM} tail -f ${REMOTE_LOG}"
