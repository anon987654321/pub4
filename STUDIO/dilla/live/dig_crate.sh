#!/bin/zsh
# Fills the crate from project/crate.yml through live/dig_crate.rb. Not
# lib/crate_dig.rb, which is the engine's archive.org and ccMixter digger.
set -euo pipefail
export PATH=/Users/mac/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin
export RBENV_VERSION=3.4.9
export DILLA_SH_TIMEOUT=1800
exec ruby "${0:h}/dig_crate.rb"
