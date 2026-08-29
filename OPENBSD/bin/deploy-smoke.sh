#!/usr/bin/env sh
# One-page post-deploy smoke — run on vm23 after vps-deploy / restarts, or from a laptop.
#
# Usage:
#   sh OPENBSD/bin/deploy-smoke.sh              # auto: local+public if rcctl present
#   sh OPENBSD/bin/deploy-smoke.sh --public     # public HTTPS only
#   sh OPENBSD/bin/deploy-smoke.sh --local      # localhost ports + rcctl only
#   ALLOW_AMBER_DOWN=1 sh OPENBSD/bin/deploy-smoke.sh   # don't fail if amber is down
#   ALLOW_BSDPORTS_DOWN=1 sh OPENBSD/bin/deploy-smoke.sh  # same for bsdports
#
# Exit 0 only when required checks pass.
#
# bsdports was the hole this script existed to cover and did not: it had no local
# check at all and its public check was optional, so the one post-deploy gate that
# is supposed to notice a dead app could not fail on the app that was found dead
# (TODO.md: amber_bsdports_stop_and_stay_down). The contract test passed
# throughout, because it asserted the URL was present rather than required.
# A waiver is now a named variable per app, so waiving is a decision that shows up
# in the command line rather than a default nobody reads.

set -eu

CURL=${CURL:-curl}
TIMEOUT=${SMOKE_TIMEOUT:-20}
MODE=${1:-auto}
ALLOW_AMBER_DOWN=${ALLOW_AMBER_DOWN:-0}
ALLOW_BSDPORTS_DOWN=${ALLOW_BSDPORTS_DOWN:-0}

failed=0
warns=0

ok()   { printf 'ok   %s\n' "$*"; }
fail() { printf 'FAIL %s\n' "$*" >&2; failed=$((failed + 1)); }
warn() { printf 'WARN %s\n' "$*" >&2; warns=$((warns + 1)); }

have_rcctl() {
  command -v rcctl >/dev/null 2>&1 || [ -x /usr/sbin/rcctl ]
}

curl_code() {
  url=$1
  code=$($CURL -sS -o /dev/null -w '%{http_code}' --max-time "$TIMEOUT" "$url" 2>/dev/null || printf '000')
  printf '%s' "$code"
}

check_http() {
  name=$1
  url=$2
  required=${3:-1}
  code=$(curl_code "$url")
  case "$code" in
    2??|3??)
      ok "$name $url ($code)"
      ;;
    *)
      if [ "$required" = "0" ]; then
        warn "$name $url ($code) optional"
      else
        fail "$name $url ($code)"
      fi
      ;;
  esac
}

check_rcctl() {
  svc=$1
  required=${2:-1}
  if ! have_rcctl; then
    return 0
  fi
  if doas -n rcctl check "$svc" >/dev/null 2>&1 || rcctl check "$svc" >/dev/null 2>&1; then
    ok "rcctl $svc"
  else
    if [ "$required" = "0" ]; then
      warn "rcctl $svc failed (optional)"
    else
      fail "rcctl $svc"
    fi
  fi
}

mem_hint() {
  if ! have_rcctl; then
    return 0
  fi
  # OpenBSD: free pages × page size is awkward; top -b one-liner when present
  if command -v top >/dev/null 2>&1; then
    line=$(top -b 2>/dev/null | sed -n 's/^Memory: //p' | head -1)
    if [ -n "$line" ]; then
      printf 'info memory: %s\n' "$line"
      case "$line" in
        *Free:\ [0-9]M*|*Free:\ [1-9][0-9]M*)
          # crude: free under ~80M is tight for a third Rails app
          free_m=$(printf '%s' "$line" | sed -n 's/.*Free: \([0-9]*\)M.*/\1/p')
          if [ -n "$free_m" ] && [ "$free_m" -lt 80 ] 2>/dev/null; then
            warn "low free RAM (~${free_m}M) — amber+brgen+master may OOM (see TODO.md multi_app_ram)"
          fi
          ;;
      esac
    fi
  fi
}

brgen_html_smoke() {
  url=${BRGEN_SMOKE_URL:-https://brgen.no/}
  html=$($CURL -sS --max-time "$TIMEOUT" "$url" 2>/dev/null || true)
  if [ -z "$html" ]; then
    fail "brgen html empty $url"
    return
  fi
  case "$html" in
    *'id="splash"'*|*'splash-title'*)
      fail "brgen splash still present on $url"
      ;;
    *)
      ok "brgen no guest splash"
      ;;
  esac
  # The nav landmark, not a tablist.
  #
  # This asked for role="tablist" until 2026-08-11 and warned on every run,
  # because brgen/app/views/shared/_nav_swiper.html.erb deliberately stopped being
  # one on 2026-08-10: dressing navigating links as tabs produced three axe
  # violations at once, and role="tablist" on <nav> overrode the navigation
  # landmark so nothing inside counted as landmark content. The check outlived the
  # shape it was written for and trained everyone to ignore a warn.
  #
  # What the decision actually preserved is what is checked now: the nav landmark
  # is present and the active entry carries aria-current, which is the correct
  # signal for navigation.
  case "$html" in
    *'id="nav_sections"'*)
      ok "brgen nav landmark present"
      ;;
    *)
      warn "brgen nav landmark not found (cache or partial HTML?)"
      ;;
  esac
  case "$html" in
    *'aria-current="page"'*)
      ok "brgen nav marks the active entry"
      ;;
    *)
      warn "brgen nav has no aria-current (front page may be the active entry)"
      ;;
  esac
}

printf 'deploy-smoke: mode=%s timeout=%ss\n' "$MODE" "$TIMEOUT"

run_local=0
run_public=0
case "$MODE" in
  --local)  run_local=1 ;;
  --public) run_public=1 ;;
  auto|"")
    if have_rcctl; then run_local=1; run_public=1
    else run_public=1
    fi
    ;;
  -h|--help)
    sed -n '2,12p' "$0"
    exit 0
    ;;
  *)
    printf 'usage: deploy-smoke.sh [--local|--public|auto]\n' >&2
    exit 2
    ;;
esac

amber_req=1
if [ "$ALLOW_AMBER_DOWN" = "1" ]; then
  amber_req=0
fi
bsdports_req=1
if [ "$ALLOW_BSDPORTS_DOWN" = "1" ]; then
  bsdports_req=0
fi

if [ "$run_local" = "1" ]; then
  printf '\n== local (vm23) ==\n'
  mem_hint
  check_rcctl master 1
  check_rcctl brgen 1
  check_rcctl amber "$amber_req"
  check_rcctl bsdports "$bsdports_req"
  check_rcctl relayd 1
  check_http master_local  "http://127.0.0.1:53187/up" 1
  check_http brgen_local   "http://127.0.0.1:38182/up" 1
  check_http amber_local   "http://127.0.0.1:61352/up" "$amber_req"
  # The local port is the check that distinguishes a shed app from a relayd
  # failure: a shed app leaves 443 answering and only this port closed.
  check_http bsdports_local "http://127.0.0.1:47312/up" "$bsdports_req"
fi

if [ "$run_public" = "1" ]; then
  printf '\n== public ==\n'
  check_http master_public  "https://ai.brgen.no/up" 1
  check_http brgen_public   "https://brgen.no/up" 1
  check_http amber_public   "https://amber.brgen.no/up" "$amber_req"
  check_http bsdports_public "https://bsdports.org/up" "$bsdports_req"
  # One asset per app, from the engine's shared/public, which the deploy ships by
  # tarring RAILS/shared wholesale rather than through the asset pipeline. Nothing
  # else here proves that tar arrived: /up answers from the app, and propshaft
  # never digests these files, so a sync that dropped public/ would look green.
  #
  # This exact font 404'd on amber for months while the stylesheet asking for it
  # returned 200, because it existed only under brgen/public — Pub4::AssetUrlLint
  # now catches that at source, but a source lint cannot prove the file shipped.
  check_http shared_font_brgen "https://brgen.no/fonts/lg.woff2" 1
  check_http shared_font_amber "https://amber.brgen.no/fonts/lg.woff2" "$amber_req"
  brgen_html_smoke
fi

printf '\n'
if [ "$failed" -ne 0 ]; then
  printf 'deploy-smoke: FAILED (%s hard, %s warn)\n' "$failed" "$warns" >&2
  exit 1
fi
printf 'deploy-smoke: ok (%s warnings)\n' "$warns"
exit 0
