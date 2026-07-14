#!/usr/bin/env zsh
set -euo pipefail

# Fix hardcoded password123 in RAILS deploy scripts (pure zsh).

SCRIPT_DIR=${0:a:h}
RAILS_ROOT=${SCRIPT_DIR:h:h:h}/RAILS

log() { print "[$(date '+%H:%M:%S')] $*" }

fix_passwords_in_file() {
  local file="$1"
  [[ -f "$file" ]] || { log "skip (missing): $file"; return 0 }

  log "fixing: $file"
  local content=$(<"$file")
  content="${content//password: \"password123\"/password: SecureRandom.alphanumeric(20)}"
  content="${content//password: \'password123\'/password: SecureRandom.alphanumeric(20)}"
  print -r -- "$content" > "$file"
  log "ok: $file"
}

log "Scanning ${RAILS_ROOT} for deploy scripts..."
typeset -a files_to_fix
files_to_fix=(${RAILS_ROOT}/*/*.sh(N))

if (( ${#files_to_fix[@]} == 0 )); then
  log "no *.sh deploy scripts found under ${RAILS_ROOT}"
  exit 0
fi

for file in "${files_to_fix[@]}"; do
  fix_passwords_in_file "$file"
done

log "done (${#files_to_fix[@]} scripts)"
