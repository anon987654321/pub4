#!/usr/bin/env zsh
# Rails app deploy — executable script. App trees live in DEPLOY/rails/<app>/.
# Routine (on vm23): cd ~/pub4/DEPLOY/rails && doas zsh DEPLOY.sh
# Default deploys brgen (core). Pass an app name or `all` for every public app.
set -euo pipefail

SCRIPT_DIR=${0:a:h}
typeset -a CORE_APPS=(brgen)
typeset -a ALL_APPS=(brgen amber bsdports hjerterom)

deploy_app() {
  typeset app=$1
  typeset script=${SCRIPT_DIR}/${app}/${app}.sh
  [[ -f $script ]] || { print -u2 "DEPLOY.sh: no script for ${app} (${script})"; exit 1 }
  print -r -- "==> ${app}"
  doas zsh "$script"
}

main() {
  if [[ ${1:-} = --help ]]; then
    print -r -- "Rails deploy (DEPLOY.sh).
Usage:
  cd ~/pub4/DEPLOY/rails && doas zsh DEPLOY.sh          # brgen (default)
  doas zsh DEPLOY.sh amber
  doas zsh DEPLOY.sh all                               # all public apps"
    exit 0
  fi

  case ${1:-brgen} in
    all)
      for app in $ALL_APPS; do deploy_app "$app"; done
      ;;
    brgen|amber|bsdports|hjerterom)
      deploy_app "$1"
      ;;
    *)
      print -u2 "DEPLOY.sh: unknown app '$1' (try brgen, amber, bsdports, hjerterom, or all)"
      exit 1
      ;;
  esac
}

main "$@"