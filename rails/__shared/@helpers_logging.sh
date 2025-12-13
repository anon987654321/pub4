#!/usr/bin/env zsh
set -euo pipefail

# Logging helper - extracted from @core_setup.sh
# Master.yml v70.0.0 compliant

log() {
    print "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}
