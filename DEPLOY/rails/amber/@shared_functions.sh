#!/usr/bin/env zsh
# Compatibility shim for older Amber deploy commands.
#
# Amber Rails application code must live as tracked files under:
#   DEPLOY/rails/amber/app
#
# Do not embed Ruby, ERB, CSS, JavaScript, models, controllers, migrations,
# or service objects in this shell helper. Deployment-only behavior belongs in
# amber.sh and common deploy helpers belong in DEPLOY/rails/@shared_functions.sh.

SCRIPT_DIR=${0:a:h}
COMMON_HELPER=${SCRIPT_DIR:h}/@shared_functions.sh

if [[ -f $COMMON_HELPER ]]; then
  . "$COMMON_HELPER"
else
  print -u2 "ERR common Rails helper not found: $COMMON_HELPER"
  return 1 2>/dev/null || exit 1
fi
