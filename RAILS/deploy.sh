#!/usr/bin/env zsh
# Compatibility entrypoint: delegate to the canonical unprivileged deploy supervisor.
# Never run checkout-owned app deployment scripts as root.
set -euo pipefail

SCRIPT_DIR=${0:a:h}
REPO_ROOT=${SCRIPT_DIR:h}

if [[ $(id -u) -eq 0 ]]; then
  print -u2 "deploy.sh: refusing to run checkout scripts as root."
  print -u2 "            Run as dev: zsh RAILS/deploy.sh [brgen|bsdports|all]"
  exit 2
fi

case ${1:-brgen} in
  all|brgen|bsdports) app=${1:-brgen} ;;
  --help|-h)
    print -r -- "usage: zsh RAILS/deploy.sh [brgen|bsdports|all]"
    exit 0
    ;;
  *)
    print -u2 "deploy.sh: unknown app '${1}'"
    exit 2
    ;;
esac

exec zsh "${REPO_ROOT}/OPENBSD/bin/vps-deploy" "$app"
