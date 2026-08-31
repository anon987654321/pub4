#!/bin/zsh
export PATH=/Users/mac/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin
export RBENV_VERSION=3.4.9
export DILLA_SH_TIMEOUT=1800
exec /opt/homebrew/bin/ruby "${0:h}/dig_crate.rb"
