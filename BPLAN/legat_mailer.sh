#!/bin/ksh
# legat_mailer.sh — build PDFs and batch-send legat applications (OpenBSD + mutt)
#
# Prerequisites on VPS:
#   pkg_add mutt chromium   # or wkhtmltopdf
#   doas rcctl enable smtpd && doas rcctl start smtpd
#   export MUTT_CONFIG=$HOME/pub4/BPLAN/etc/muttrc   (or copy to ~/.muttrc)
#
# Usage:
#   ./legat_mailer.sh build              # HTML + PDF for all sendable
#   ./legat_mailer.sh list               # 68 sendable with e-post
#   ./legat_mailer.sh batches            # named batches (bolig_asap, helse, …)
#   ./legat_mailer.sh dry-run bolig_asap # preview .eml in legats/outbox/
#   ./legat_mailer.sh send bolig_asap    # actually mail (LEGAT_SEND=1)
#   LEGAT_SEND=1 FORCE_IN=1 ./legat_mailer.sh send innovasjon  # includes IN
#
set -e

ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"

RUBY=${RUBY:-ruby}
GROK="$ROOT/grok_send_legats.rb"
PDF_SCRIPT="$ROOT/scripts/build_pdfs.rb"

export LEGAT_FROM=${LEGAT_FROM:-bergen@pub.attorney}
export LEGAT_DAILY_CAP=${LEGAT_DAILY_CAP:-5}
export CHROME_BIN=${CHROME_BIN:-chromium}
export MUTT_CONFIG=${MUTT_CONFIG:-$ROOT/etc/muttrc}

usage() {
  echo "Usage: $0 {build|pdfs|list|batches|dry-run|send} [batch_or_id ...]" >&2
  echo "  send requires LEGAT_SEND=1 (safety latch)" >&2
  exit 1
}

check_mailer() {
  command -v "$RUBY" >/dev/null 2>&1 || { echo "missing ruby" >&2; exit 1; }
  command -v mutt >/dev/null 2>&1 || { echo "missing mutt — pkg_add mutt" >&2; exit 1; }
  if command -v rcctl >/dev/null 2>&1; then
    rcctl check smtpd 2>/dev/null | grep -q '(ok)' || echo "warn: smtpd not running — doas rcctl start smtpd" >&2
  fi
}

cmd=${1:-}
shift || true

case "$cmd" in
  build)
    "$RUBY" build_legats.rb
    "$RUBY" "$PDF_SCRIPT" --all
    echo "built HTML + PDFs"
    ;;
  pdfs)
    "$RUBY" "$PDF_SCRIPT" --all "$@"
    ;;
  list)
    "$RUBY" "$GROK" --list-sendable
    ;;
  batches)
    "$RUBY" "$GROK" --list-batches
    ;;
  dry-run)
    [ $# -gt 0 ] || usage
    for target in "$@"; do
      if "$RUBY" "$GROK" --list-batches 2>/dev/null | grep -q "^${target}:"; then
        "$RUBY" "$GROK" --batch "$target" --dry-run
      else
        "$RUBY" "$GROK" --id "$target" --dry-run
      fi
    done
    ;;
  send)
    [ "${LEGAT_SEND:-0}" = "1" ] || {
      echo "Refusing send without LEGAT_SEND=1" >&2
      echo "Dry-run first: $0 dry-run <batch>" >&2
      exit 1
    }
    check_mailer
    [ $# -gt 0 ] || usage
    for target in "$@"; do
      if "$RUBY" "$GROK" --list-batches 2>/dev/null | grep -q "^${target}:"; then
        "$RUBY" "$GROK" --batch "$target" --confirm
      else
        "$RUBY" "$GROK" --id "$target" --confirm
      fi
    done
    ;;
  -h|--help|"") usage ;;
  *) usage ;;
esac