```zsh
#!/usr/bin/env zsh
# Modernize all .sh files to pure zsh patterns per master.yml v17.0.0

setopt err_return no_unset pipe_fail extended_glob

typeset -a files errors
files=(**/*.sh(.ND))

for file in $files; do
  [[ $file == */modernize_zsh.sh ]] && continue

  printf "Processing: %s\n" "$file"

  # Check if file exists and is readable
  if [[ ! -f "$file" || ! -r "$file" ]]; then
    errors+=("$file: File not found or unreadable")
    continue
  fi

  # Handle symlinks by resolving to actual file
  if [[ -L "$file" ]]; then
    local resolved_file=$(readlink -f "$file" 2>/dev/null || realpath "$file" 2>/dev/null)
    if [[ -n "$resolved_file" && -f "$resolved_file" ]]; then
      file="$resolved_file"
    else
      errors+=("$file: Symlink target not found or inaccessible")
      continue
    fi
  fi

  # Create backup with verification
  if ! cp "$file" "${file}.bak"; then
    errors+=("$file: Backup failed")
    continue
  fi

  # Platform-specific sed in-place option
  local sed_in_place
  case $(uname) in
    Darwin) sed_in_place=(-i '') ;;
    *) sed_in_place=(-i) ;;
  esac

  # Test sed commands first with dry run
  local sed_errors=()
  for pattern in \
    's/local /typeset /g' \
    's/\${\([^}]*\),,}/\${\1:l}/g' \
    's/\${\([^}]*\)\^\^}/\${\1:u}/g' \
    's/\${\([^}]*\)\^}/\${(C)\1}/g'
  do
    if ! sed -n "${pattern}p" "$file" | head -1 >/dev/null 2>&1; then
      sed_errors+=("Pattern '${pattern}' failed dry run")
    fi
  done

  if (( ${#sed_errors} > 0 )); then
    errors+=("$file: Sed validation failed: ${sed_errors[*]}")
    continue
  fi

  # Apply transformations
  for pattern in \
    's/local /typeset /g' \
    's/\${\([^}]*\),,}/\${\1:l}/g' \
    's/\${\([^}]*\)\^\^}/\${\1:u}/g' \
    's/\${\([^}]*\)\^}/\${(C)\1}/g'
  do
    if ! sed "${sed_in_place[@]}" "${pattern}" "$file"; then
      errors+=("$file: Sed failed for pattern '${pattern}'")
      # Restore from backup on failure
      cp "${file}.bak" "$file"
      continue 2
    fi
  done

  printf "  ✓ Modernized\n"
done

if (( ${#errors} > 0 )); then
  printf "\nErrors occurred:\n"
  printf "  %s\n" "${errors[@]}"
fi

printf "\nDone: %d files processed (%d errors)\n" ${#files} ${#errors}
```
