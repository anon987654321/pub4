#!/usr/bin/env zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_g
set -euo pipefail

# Gather target files
typeset -a files errors
files=(**/*.sh)

# Default sed patterns (override by exporting sed_patterns)
if (( ${#sed_patterns[@]} == 0 )); then
  sed_patterns=(
    's/\r$//g'               # strip CR
    's/[[:space:]]+$//g'     # trim trailing whitespace
    's/^[[:space:]]+//'      # trim leading whitespace
  )
fi

# Choose correct -i syntax for sed
case $(uname) in
  Darwin) sed_in_place=(-i '') ;;
  *)      sed_in_place=(-i) ;;
esac

for file in $files; do
  [[ $file == */modernize_zsh.sh ]] && continue

  [[ -f $file && -r $file ]] || {
    errors+=("$file: not found or unreadable")
    continue
  }

  # Resolve symlink to real file
  if [[ -L $file ]]; then
    real=$(readlink -f $file 2>/dev/null) || {
      errors+=("$file: cannot resolve symlink")
      continue
    }
    [[ -f $real ]] && file=$real || {
      errors+=("$file: symlink target missing")
      continue
    }
  fi

  # Make a backup if none exists
  if [[ ! -f ${file}.bak ]]; then
    cp --preserve=mode,timestamps "$file" "${file}.bak" || {
      errors+=("$file: backup failed")
      continue
    }
  fi

  # Dry‑run all patterns
  for pat in "${sed_patterns[@]}"; do
    if ! sed -n "${sed_in_place[@]}" -e "$pat" -e 'q' "$file" >/dev/null 2>&1; then
      errors+=("$file: dry‑run failed for $pat")
      continue 2
    fi
  done

  # Apply patterns
  for pat in "${sed_patterns[@]}"; do
    if ! sed "${sed_in_place[@]}" -e "$pat" "$file"; then
      errors+=("$file: transformation failed for $pat")
      continue 2
    fi
  done
done

if (( ${#errors[@]} )); then
  printf "Errors:\n%s\n" "${errors[@]}"
  exit 1
fi