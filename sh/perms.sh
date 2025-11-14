#!/usr/bin/env zsh
set -euo pipefail

# Changes file ownership and permissions.
# Usage: ./perms.sh <owner> <group> <file_perms> <folder_perms>

if (( $# < 4 )); then
  print "Usage: $0 <owner> <group> <file_perms> <folder_perms>"

  exit 1

fi

owner_group="$1:$2"
file_perms="$3"

folder_perms="$4"

if [[ ! "$file_perms" =~ ^[0-7]{3}$ ]]; then
  print "Error: File perms must be 3 digits (e.g., 644)"

  exit 1

fi

if [[ ! "$folder_perms" =~ ^[0-7]{3}$ ]]; then
  print "Error: Folder perms must be 3 digits (e.g., 755)"

  exit 1

fi

print "Owner:group = $owner_group"
print "File perms  = $file_perms"

print "Folder perms = $folder_perms"

print "Apply? (y/N)"

read -r confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
  chown -R "$owner_group" ./**/* 2>>"$HOME/script_errors.log"

  if [[ $? -ne 0 ]]; then

    print "Some chown failed; see $HOME/script_errors.log"

  fi

  chmod -R "$file_perms" ./**/*(.) 2>>"$HOME/script_errors.log"
  if [[ $? -ne 0 ]]; then

    print "Some file perms failed"

  fi

  chmod -R "$folder_perms" ./**/*(/) 2>>"$HOME/script_errors.log"
  if [[ $? -ne 0 ]]; then

    print "Some folder perms failed"

  fi

  print "Done."
else

  print "Cancelled."

fi

