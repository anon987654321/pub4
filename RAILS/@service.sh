#!/usr/bin/env zsh
# @service.sh — backward-compat alias; canonical implementation is _service.sh
typeset _deploy_sh_dir=${${(%):-%x}:A:h}
. "${_deploy_sh_dir}/_service.sh"