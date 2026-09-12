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
#
# SSH_HOST here is the host ALONE — the login is SSH_USER, and they are joined as
# ${SSH_USER}@${SSH_HOST} below. config_drift_gate.rb and bin/deploy-diff.sh give
# the same variable the opposite meaning, login@host in one string, so exporting
# one file's SSH_HOST into another's yields dev@dev@brgen.no and every ssh fails.

: "${SSH_USER:=dev}"
: "${SSH_HOST:=46.23.89.226}"
: "${SSH_KEY:=${HOME}/.ssh/id_ed25519_brgen}"
: "${REMOTE_PUB4:=/home/dev/pub4}"

# One copy of the usage, above the functions rather than in the dispatch at the
# foot of the file, and reachable as -h so an operator does not have to run the
# script with no argument to be told what it takes.
ssh_vm23_usage() {
  print -r -- "usage: ssh_vm23.sh <remote-command>
       ssh_vm23.sh exec <remote-command>
       ssh_vm23.sh tmux <session> <remote-command>

Env: SSH_USER SSH_HOST SSH_KEY REMOTE_PUB4"
}

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

if [[ $ZSH_EVAL_CONTEXT == toplevel ]]; then
  case "${1:-}" in
    -h|--help)
      ssh_vm23_usage
      exit 0
      ;;
    tmux)
      shift
      vm23_tmux "$@"
      ;;
    exec)
      shift
      vm23_ssh "$@"
      ;;
    "")
      ssh_vm23_usage >&2
      exit 2
      ;;
    *)
      vm23_ssh "$@"
      ;;
  esac
fi
