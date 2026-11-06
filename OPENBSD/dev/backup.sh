#!/usr/bin/env zsh
set -euo pipefail

# Archives folders to dated .tgz files, skips unchanged ones.

# Usage: ./backup.sh [directory]

log_error() {

  print "[$(date +"%Y-%m-%d %H:%M:%S")] $1" >> "$HOME/script_errors.log"

}

dir="${1:-.}"

checksum_file="$dir/.backup_checksums"

date_format=$(date +"%Y%m%d")

cd "$dir" || exit 1

# Load prior checksums to check for changes

typeset -A old_checksums

if [[ -f "$checksum_file" ]]; then

  while read -r folder checksum; do

    old_checksums["$folder"]="$checksum"

  done < "$checksum_file"

fi

typeset -A new_checksums

for subdir in */(N); do

  folder="${subdir%/}"

  # Pure zsh: glob for files, collect MD5s, sort with ${(o)arr}, then hash

  typeset -a file_hashes=()

  for file in "$folder"/**/*(.N); do

    file_hashes+=($(md5 -q "$file" 2>/dev/null))

  done

  # Sort using pure zsh and create final checksum

  typeset -a sorted_hashes=( ${(o)file_hashes} )

  checksum=$(print -l "${sorted_hashes[@]}" | md5 -q)

  backup_file="${folder}_${date_format}.tgz"

  # :- on both reads. `set -u` is on and these are associative-array lookups,
  # so an unseen folder is an unset parameter and zsh aborts on it. Every
  # folder is unseen on a first run — the run where there is no checksum file
  # at all — so a first run died on the first folder, every time.
  if [[ -z "${old_checksums[$folder]:-}" || "${old_checksums[$folder]:-}" != "$checksum" ]]; then

    print "Backing up: $folder -> $backup_file"

    # In the if-condition, not before it. This was a bare `tar` followed by
    # `if [[ $? -ne 0 ]]`, and `set -e` is on, so a failing tar killed the
    # script at that line: the handler under it had never run once, and no
    # folder after the failing one was reached. A command in an if-condition is
    # the one place set -e stands aside.
    #
    # stderr goes to the error log rather than /dev/null. The reason a backup
    # failed is the whole content of the report.
    if tar cvzf "$backup_file" "$folder" 2>>"$HOME/script_errors.log"; then

      print "Created: $backup_file"

      new_checksums["$folder"]="$checksum"

    else

      log_error "tar failed for $backup_file"

      print "Failed: $backup_file"

      # tar writes what it managed to read before giving up, so a failure
      # leaves a short .tgz sitting next to the good ones with nothing to
      # distinguish it. Removing it is what makes the next run's retry the
      # only copy there is.
      rm -f "$backup_file"

    fi

  else

    print "Skipped (no changes): $folder"

    new_checksums["$folder"]="$checksum"

  fi

done

# Updates checksum file for next run

for folder in ${(k)new_checksums}; do

  print "$folder ${new_checksums[$folder]}"

done > "$checksum_file"
