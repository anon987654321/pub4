#!/usr/bin/env zsh
# Run on vm23 as dev. The console recovery path (vps_console.exp start_install,
# vps_drop_install.exp) drops this file into /tmp by name, so it stays; the work
# is vps_install_all.sh's, which is the one bootstrap-on-box script.
# Usage: zsh OPENBSD/vps_on_vm_install.sh
set -euo pipefail
exec zsh "${PUB4_ROOT:-/home/dev/pub4}/OPENBSD/vps_install_all.sh" "$@"
