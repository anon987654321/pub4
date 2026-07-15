#!/usr/bin/env zsh
# @core.sh — backward-compat alias; canonical implementation is _core.sh
typeset _deploy_sh_dir=${${(%):-%x}:A:h}
. "${_deploy_sh_dir}/_core.sh"