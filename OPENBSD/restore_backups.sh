#!/usr/bin/env zsh
# Restore Rails SQLite databases from on-disk Litestream replicas (vm23).
# Stops app services, runs litestream restore, restarts services.
#
# Usage (on vm23):
#   DRY_RUN=1 zsh OPENBSD/restore_backups.sh          # print plan only
#   zsh OPENBSD/restore_backups.sh brgen              # one app
#   zsh OPENBSD/restore_backups.sh                    # all apps in etc/litestream.yml
#
# For repo-archaeology (pub3 heredocs), use extract_legacy_installers.sh instead.
#
# Every precondition below is a hard failure, not a skip. On vm23 litestream is
# absent and /var/backups/litestream/ is empty, so a skipping restore walked all
# three apps, restored none of them and printed "done" — a disaster-recovery
# script that reports success is worse than one that is missing, because it is
# read as evidence. The working backup is OPENBSD/bin/dr-pull, whose snapshots
# live on the operator Mac; see RUNBOOK.md, "Backups".

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
CONFIG="${LITESTREAM_CONFIG:-/etc/litestream.yml}"
DRY_RUN="${DRY_RUN:-0}"
APPS=("${@}")

log() { printf '[restore] %s\n' "$*"; }

discover_apps() {
  if (( ${#APPS[@]} > 0 )); then
    print -l -- "${APPS[@]}"
    return
  fi
  [[ -f $CONFIG ]] || { log "missing litestream config: $CONFIG"; exit 1; }
  ruby - "$CONFIG" <<'RUBY'
require 'yaml'
config = YAML.load_file(ARGV[0])
Array(config['dbs']).each do |entry|
  path = entry['path'].to_s
  next unless path =~ %r{/home/([^/]+)/}
  puts $1
end
RUBY
}

require_litestream() {
  whence litestream >/dev/null 2>&1 && return 0
  log "FAIL — no litestream binary on this host, so nothing here can restore anything."
  log "       litestream is not in OpenBSD ports; /var/backups/litestream/ is empty."
  log "       Restore from a dr-pull snapshot instead: ruby OPENBSD/bin/dr-pull --check"
  exit 1
}

restore_app() {
  local app="$1"
  local storage="/home/${app}/app/storage"
  local replica="file:///var/backups/litestream/${app}"

  [[ -d $storage ]] || { log "FAIL $app — missing $storage"; exit 1 }
  [[ -d "/var/backups/litestream/${app}" ]] || { log "FAIL $app — missing replica $replica"; exit 1 }

  local -a dbs
  dbs=("$storage"/*.sqlite3(N))
  if (( ${#dbs[@]} == 0 )); then
    log "FAIL $app — no *.sqlite3 in $storage"
    exit 1
  fi

  log "stopping $app"
  if [[ $DRY_RUN != 1 ]]; then
    doas rcctl stop "$app" 2>/dev/null || true
  fi

  local db
  for db in "${dbs[@]}"; do
    log "restore $db <= $replica"
    if [[ $DRY_RUN == 1 ]]; then
      log "dry-run: litestream restore -config $CONFIG -o $db $replica"
    else
      doas -u "$app" litestream restore -config "$CONFIG" -o "$db" "$replica"
    fi
  done

  log "starting $app"
  if [[ $DRY_RUN != 1 ]]; then
    doas rcctl start "$app"
    doas rcctl check "$app"
  fi
}

main() {
  [[ $DRY_RUN == 1 ]] || require_litestream
  local app
  while IFS= read -r app; do
    [[ -n $app ]] || continue
    restore_app "$app"
  done < <(discover_apps)
  log "done"
}

main "$@"
