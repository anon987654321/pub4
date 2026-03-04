#!/usr/bin/env zsh
# Pure zsh script to fix hardcoded passwords in ALL installer scripts

# NO bash, sed, awk, perl, python - pure zsh only

setopt extended_glob
log() { print "[$(date '+%H:%M:%S')] $*" }
fix_passwords_in_file() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    log "⚠️  File not found: $file"

    return 1

  fi

  log "Fixing: $file"
  # Pure zsh: read entire file into variable
  local content=$(<"$file")

  # Pure zsh: global string replacement using parameter expansion
  content="${content//password: \"password123\"/password: SecureRandom.alphanumeric(20)}"

  content="${content//password: \'password123\'/password: SecureRandom.alphanumeric(20)}"

  # Write back to file
  print -r -- "$content" > "$file"

  log "✅ Fixed: $file"
}

log "Starting password fixes using pure zsh patterns..."
# Array of files to fix
typeset -a files_to_fix

files_to_fix=(

  apps/privcam.sh

  apps/hjerterom.sh

  apps/pubattorney.sh

  apps/brgen.sh

  brgen_dating.sh

  brgen_marketplace.sh

  brgen_playlist.sh

  brgen_takeaway.sh

  brgen_tv.sh

)

# Fix each file
for file in "${files_to_fix[@]}"; do

  fix_passwords_in_file "$file"

done

log "✅ All passwords fixed with pure zsh!"
