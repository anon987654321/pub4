#!/usr/bin/env zsh
set -euo pipefail
# Shared SSH helper for vm23 (dev@46.23.89.226).
#
# Source from deploy scripts:
#   source OPENBSD/lib/ssh_vm23.sh
#   vm23_ssh 'uname -a'
#   vm23_tmux deploy "doas zsh OPENBSD/OPERATOR.sh 2>&1 | tee /tmp/deploy.log"
#
# Direct invocation:
#   zsh OPENBSD/lib/ssh_vm23.sh 'cd /home/dev/pub4 && git pull'
#   zsh OPENBSD/lib/ssh_vm23.sh tmux deploy 'doas zsh OPENBSD/OPERATOR.sh'
#
# Env: SSH_USER SSH_HOST SSH_KEY REMOTE_PUB4

: "${SSH_USER:=dev}"
: "${SSH_HOST:=46.23.89.226}"
: "${SSH_KEY:=${HOME}/.ssh/id_ed25519_brgen}"
: "${REMOTE_PUB4:=/home/dev/pub4}"

typeset -ga VM23_SSH_OPTS=(
  -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new
  -o ConnectTimeout=15
)
[[ -f $SSH_KEY ]] && VM23_SSH_OPTS+=(-i "$SSH_KEY")

vm23_ssh() {
  ssh "${VM23_SSH_OPTS[@]}" "${SSH_USER}@${SSH_HOST}" "$@"
}

vm23_tmux() {
  typeset session=$1
  shift
  typeset cmd=$*
  vm23_ssh \
    "tmux has-session -t ${session} 2>/dev/null && tmux kill-session -t ${session}; \
     tmux new-session -d -s ${session} ${(q)cmd}"
}

if [[ $(basename -- "$0") == ssh_vm23.sh ]]; then
  case "${1:-}" in
    tmux)
      shift
      vm23_tmux "$@"
      ;;
    exec)
      shift
      vm23_ssh "$@"
      ;;
    "")
      print -u2 "usage: ssh_vm23.sh <remote-command>"
      print -u2 "       ssh_vm23.sh tmux <session> <remote-command>"
      exit 2
      ;;
    *)
      vm23_ssh "$@"
      ;;
  esac
fi
