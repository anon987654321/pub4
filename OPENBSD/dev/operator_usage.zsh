#!/usr/bin/env zsh
# Command-line usage text for OPENBSD/OPERATOR.sh.
# Sourced by the entrypoint; defines usage without executing it.

usage() {
  print -r -- "OpenBSD vm23 deploy (OPERATOR.sh). Config trees: etc/ usr/ var/ → /.
Usage:
  cd ~/pub4 && doas zsh OPENBSD/OPERATOR.sh

Default: install configs, validate pf/relayd, restart services.

Rare:
  doas zsh OPERATOR.sh --first-install
  doas zsh OPERATOR.sh --stage-1        # requires I_UNDERSTAND_DNS_WIPE=1
  doas zsh OPERATOR.sh --stage-2

--sync-configs is an alias for the default.

Env:
  RUN_PRODUCTION_SEEDS=1   run db:seed during app bootstrap (default 0: never seed production)
  I_UNDERSTAND_DNS_WIPE=1  required by --stage-1"
}
