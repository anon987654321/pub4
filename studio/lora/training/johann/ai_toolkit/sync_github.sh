#!/bin/sh
# Thin wrapper: names the subject, then hands over to the shared toolkit.
set -eu
SUBJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
export SUBJECT_DIR
exec "$SUBJECT_DIR/../../../_toolkit/sync_github.sh" "$@"
