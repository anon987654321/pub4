#!/usr/bin/env zsh
# @sync.sh — backward-compat alias; canonical implementation is _sync.sh
typeset _deploy_sh_dir=${${(%):-%x}:A:h}
. "${_deploy_sh_dir}/_sync.sh"