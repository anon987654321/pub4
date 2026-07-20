#!/bin/ksh
# Verify Solid Queue supervisor is alive for a Rails app on vm23.
set -eu

app=${1:-}
[[ -n $app ]] || { print -u2 "usage: solid_queue_proof.sh APP"; exit 2; }

repo=${PUB4_ROOT:-/home/dev/pub4}
ruby=${SOLID_QUEUE_PROOF_RUBY:-ruby34}
proof_rb=$repo/OPENBSD/solid_queue_proof.rb

[[ -f $proof_rb ]] || { print -u2 "missing $proof_rb"; exit 1; }

doas "$ruby" "$proof_rb" "$app"
