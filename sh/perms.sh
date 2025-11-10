#!/bin/sh
set -euo pipefail

#!/usr/bin/env zsh
# Changes file ownership and permissions.

# Usage: ./perms.sh <owner> <group> <file_perms> <folder_perms>
set -e
if (( $# < 4 )); then

  echo "Usage: $0 <owner> <group> <file_perms> <folder_perms>"

  exit 1
fi
owner_group="$1:$2"
file_perms="$3"

folder_perms="$4"
if [[ ! "$file_perms" =~ ^[0-7]{3}$ ]]; then
  echo "Error: File perms must be 3 digits (e.g., 644)"

  exit 1
fi
if [[ ! "$folder_perms" =~ ^[0-7]{3}$ ]]; then
  echo "Error: Folder perms must be 3 digits (e.g., 755)"
  exit 1
fi
echo "Owner:group = $owner_group"
echo "File perms  = $file_perms"

echo "Folder perms = $folder_perms"
echo "Apply? (y/N)"
read -r confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
  chown -R "$owner_group" ./**/* 2>>"$HOME/script_errors.log"
  if [[ $? -ne 0 ]]; then
    echo "Some chown failed; see $HOME/script_errors.log"
  fi
  chmod -R "$file_perms" ./**/*(.) 2>>"$HOME/script_errors.log"
  if [[ $? -ne 0 ]]; then

    echo "Some file perms failed"
  fi
  chmod -R "$folder_perms" ./**/*(/) 2>>"$HOME/script_errors.log"
  if [[ $? -ne 0 ]]; then

    echo "Some folder perms failed"
  fi
  echo "Done."
else

  echo "Cancelled."
fi
