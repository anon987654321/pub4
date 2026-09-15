#!/usr/bin/env zsh
# Workstation helper: copy vps_install_all.sh to VM via hypervisor jump and run it.
#
# A recovery path nothing runs. It bootstraps a fresh VM through the hypervisor
# jump, the only route that exists before ssh to the VM works. Unexercised, so read
# it before running it; removing it decides the capability is unwanted, which is
# the operator's call.
set -euo pipefail

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  print "usage: zsh OPENBSD/bin/vps_run_remote.sh"
  print "  upload vps_install_all.sh through the server4 hypervisor jump and start it under nohup"
  exit 0
fi

SCRIPT_DIR=${0:a:h}
INSTALL_SH=${SCRIPT_DIR}/vps_install_all.sh
# The VM's login, host and key are lib/ssh_vm23.sh's, the one copy of them.
source "${SCRIPT_DIR:h}/lib/ssh_vm23.sh"
KEY=$SSH_KEY
VM=${SSH_USER}@${SSH_HOST}
HYP=${HYPERVISOR:-dev@server4.openbsd.amsterdam}
HYP_PORT=${HYP_PORT:-31415}
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
