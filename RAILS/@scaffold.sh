#!/usr/bin/env zsh
set -euo pipefail
# @scaffold.sh — backward-compat alias; canonical implementation is _scaffold.sh
typeset _deploy_sh_dir=${${(%):-%x}:A:h}
. "${_deploy_sh_dir}/_scaffold.sh"
