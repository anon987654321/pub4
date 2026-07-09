#!/bin/sh
# DEPRECATED — pub4-shared engine owns all frontend baselines.
# Use: gem "pub4-shared", path: "../../shared" + bundle install
# See RAILS/shared/WIRING_NOTES.md
set -eu
printf '%s\n' "install_frontend_baseline.sh is deprecated." \
  "Shared views, helpers, concerns, and JS load via the pub4-shared engine." \
  "Run bundle install in each app instead."
exit 0