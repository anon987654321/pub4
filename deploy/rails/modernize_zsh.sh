zsh
#!/usr/bin/env zsh
# Modernize all .sh files to pure zsh patterns per master.yml v17.0.0

emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob

typeset -a files errors
files=("${(f)$(find . -name '*.sh' -type f ! -name 'modernize_zsh.sh' -print0 | xargs -0)}")

for file in $files; do
  printf "Processing: %s\n" "$file"

  if [[ ! -f "$file" || ! -r "$file" ]]; then
    errors+=("$file: File not found or unreadable")
    continue
  fi

  cp "$file" "${file}.bak" || { errors+=("$file: Backup failed"); continue; }

  # Replace local → typeset
  sed -i 's/local /typeset /g' "$file" || {; }

  # Replace ${var,,} → ${var:l} (bash lowercase to zsh)
  sed -i 's/\${\([^}]*\),,}/\${\1:l}/g' "$file" || { errors+=("$file: sed lowercase failed"); continue; }

  # Replace ${var^^} → ${var:u} (bash uppercase to zsh)
  sed -i 's/\${\([^}]*\)\^\^}/\${\1 uppercase failed"); continue; }

  # Replace ${var^} → ${(C)var} (bash capitalize to zsh)
  sed -${(C)\1}/g' "$file" || { errors+=("$file: sed capitalize failed"); continue; }

  printf "  ✓ Modernized\n"
done

if (( ${#errors} > 0 )); then
  printf "\nErrors occurred:\n"
  printf "  %s\n" "${errors[@]}"
fi

printf "\nDone: %d files processed (%d errors)\n" ${#files} ${#errors}
```
