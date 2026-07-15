#!/usr/bin/env zsh
# @runtime_gate.sh — backward-compat alias; canonical implementation is _runtime_gate.sh
typeset _deploy_sh_dir=${${(%):-%x}:A:h}
. "${_deploy_sh_dir}/_runtime_gate.sh"