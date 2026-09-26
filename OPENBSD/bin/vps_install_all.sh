#!/usr/bin/env zsh
# Run ON the VPS (vm23) as dev — installs MASTER web + each Rails app deploy script.
# The one bootstrap-on-box script: vps_on_vm_install.sh execs this file.
# Usage: zsh OPENBSD/bin/vps_install_all.sh     (LOG=/path to choose the log file)
set -euo pipefail

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  print "usage: zsh OPENBSD/bin/vps_install_all.sh — bundle and precompile MASTER, then every apps.yml app's deploy script"
  exit 0
fi

PUB4=${PUB4:-/home/dev/pub4}
LOG=${LOG:-/tmp/pub4_install_$(date +%Y%m%d_%H%M%S).log}

exec > >(tee -a "$LOG") 2>&1

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" }

log "pub4 install — log: $LOG"
# ruby34, not awk, and the pattern changed with it: OpenBSD vmstat -s writes
# "53853 pages free" and has no line matching /free memory/ at all, so the awk
# this replaces printed an empty figure on every run it ever made.
log "free memory: $(vmstat -s | ruby34 -e 'puts $stdin.read[/^\s*(\d+)\s+pages free/, 1].to_s + " pages free"' 2>/dev/null || print unknown)"

# Every fallible step below logs a WARN and continues, and the script used to end
# on `doas rcctl check master || true` — so a run that deployed nothing exited 0.
# The failures are counted from here and the exit status carries them.
failed=0

if [[ -d ${PUB4}/.git ]]; then
  log "git pull"
  # --ff-only and never a stash: a stashed Gemfile.lock on this box once took
  # master down, and a stash hides local edits where nobody looks for them.
  git -C "$PUB4" pull --ff-only origin main || log "WARN: git pull failed (continuing with tree on disk)"
  git -C "$PUB4" log -1 --oneline
fi

log "=== MASTER CLI + web ==="
[[ -d ${PUB4}/MASTER ]] || { log "ERR: MASTER missing"; exit 1 }
cd "${PUB4}/MASTER"
bundle install
cd "${PUB4}/MASTER/web"
bundle config set --local path vendor/bundle
bundle install
RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile
bundle exec ruby "${PUB4}/MASTER/gates/runner.rb" master_web_assets
doas rcctl restart master 2>/dev/null || doas rcctl start master
doas rcctl check master || { log "WARN: master not ok"; failed=$((failed + 1)); }

typeset -a APPS
APPS=(${(f)"$(ruby34 -ryaml -e 'puts YAML.safe_load_file(ARGV[0]).fetch("apps").keys' "${PUB4}/RAILS/apps.yml")"})
(( ${#APPS} )) || { log "ERR: no apps read from ${PUB4}/RAILS/apps.yml"; exit 1 }

for app in $APPS; do
  typeset script="${PUB4}/RAILS/${app}/${app}.sh"
  log "=== Rails: ${app} ==="
  if [[ ! -f $script ]]; then
    log "WARN: missing $script"
    failed=$((failed + 1))
    continue
  fi
  # Scripts call doas internally; do not wrap in doas (nested doas → "Operation not permitted").
  if ! zsh "$script"; then
    log "WARN: ${app} deploy script failed"
    failed=$((failed + 1))
  elif doas rcctl check "$app" 2>/dev/null; then
    log "ok: ${app}"
  else
    log "WARN: ${app} check failed"
    failed=$((failed + 1))
  fi
done

log "=== summary ==="
for app in $APPS; do
  printf '  %s: ' "$app"
  doas rcctl check "$app" 2>/dev/null || print "not running"
done
doas rcctl check master 2>/dev/null || true
if (( failed > 0 )); then
  log "FAILED: $failed step(s) — $LOG"
  exit 1
fi
log "finished — $LOG"
