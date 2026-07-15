#!/usr/bin/env zsh
# @deploy.sh — backward-compat alias; canonical orchestrator is _deploy.sh
typeset _deploy_sh_dir=${${(%):-%x}:A:h}
. "${_deploy_sh_dir}/_deploy.sh"