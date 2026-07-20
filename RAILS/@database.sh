#!/usr/bin/env zsh
set -euo pipefail
# @database.sh — backward-compat alias; canonical implementation is _database.sh
typeset _deploy_sh_dir=${${(%):-%x}:A:h}
. "${_deploy_sh_dir}/_database.sh"
