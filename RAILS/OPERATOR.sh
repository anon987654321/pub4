#!/usr/bin/env zsh
# Rails app deploy — executable script. App trees live in RAILS/<app>/.
# Routine (on vm23): cd ~/pub4/RAILS && doas zsh OPERATOR.sh
# Default deploys brgen (core). Pass an app name or `all` for every public app.
set -euo pipefail

SCRIPT_DIR=${0:a:h}
typeset -a CORE_APPS=(brgen)
typeset -a ALL_APPS=(brgen amber bsdports)

deploy_app() {
  typeset app=$1
  typeset script=${SCRIPT_DIR}/${app}/${app}.sh
  [[ -f $script ]] || { print -u2 "OPERATOR.sh: no script for ${app} (${script})"; exit 1 }
  print -r -- "==> ${app}"
  doas zsh "$script"
}

main() {
  if [[ ${1:-} = --help ]]; then
    print -r -- "Rails deploy (OPERATOR.sh).
Usage:
  cd ~/pub4/RAILS && doas zsh OPERATOR.sh          # brgen (default)
  doas zsh OPERATOR.sh amber
  doas zsh OPERATOR.sh all                               # all public apps"
    exit 0
  fi

  case ${1:-brgen} in
    all)
      for app in $ALL_APPS; do deploy_app "$app"; done
      ;;
    brgen|amber|bsdports)
      deploy_app "$1"
      ;;
    *)
      print -u2 "OPERATOR.sh: unknown app '$1' (try brgen, amber, bsdports, or all)"
      exit 1
      ;;
  esac
}

main "$@"
