

#!/usr/bin/env zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_g

typeset -a files errors
files=(**/*.sh)

for file in $files; do
    [[ $file == */modernize_zsh.sh ]] && continue

    printf "Processing: %s\n" "$file"

    if [[ ! -f "$file" || ! -r "$file" ]]; then
        errors+=("$file: File not found or unreadable")
    fi

    if [[ -L "$file" ]]; then
        if resolved_file=$(readlink -f "$file" 2>/dev/null) && [[ -f "$resolved_file" ]]; then
            file="$resolved_file"
        else
            errors+=("$file: Symlink target not found or inaccessible")
        fi
    fi

    if [[ -f "${file}.bak" ]]; then
        printf "Backup already exists: %s\n" "${file}.bak"
    else
        if ! cp "$file" "${file}.bak"; then
            errors+=("$file: Backup failed")
        fi
    fi

    typeset sed_in_place
    case $(uname) in
        Darwin) sed_in_place=(-i '') ;;
        *) sed_in_place=(-i) ;;
    esac

    typeset pattern_failed=0
    for pattern in "${sed_patterns[@]}"; do
        if ! sed -n "${sed_in_place[@]}" -e "$pattern" -e 'q' "$file" >/dev/null 2>&1; then
            errors+=("$file: sed dry run failed for pattern: $pattern")
        fi
    done

    typeset apply_failed=0
    for pattern in "${sed_patterns[@]}"; do
        if ! sed "${sed_in_place[@]}" -e "$pattern" "$file"; then
            errors+=("$file: sed transformation failed for pattern: $pattern")
        fi
    done
done

# Report all errors and exit with 1 if any occur
if (( ${#errors[@]} > 0 )); then
    printf "Errors:\n%s\n" "${errors[@]}"
    exit 1
fi
