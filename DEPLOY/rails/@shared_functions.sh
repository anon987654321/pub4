#!/usr/bin/env zsh
# @shared_functions.sh — sources all topic files
# Source this file; do not execute directly.
set -euo pipefail

_dir=${0:A:h}
source "$_dir/@core.sh"
source "$_dir/@assets.sh"
source "$_dir/@server.sh"
source "$_dir/@frontend.sh"
source "$_dir/@views.sh"
source "$_dir/@social.sh"
