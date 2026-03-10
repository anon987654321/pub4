#!/usr/bin/env zsh
# Modernize all .sh files to pure zsh patterns per master.yml v17.0.0

setopt err_return no_unset pipe_fail extended_glob

typeset -a files errors
files=(**/*.sh(.ND))

# Define sed patterns with better specificity
typeset -a sed_patterns=(
    's/\blocal\s+([a-zA-Z_][a-zA-Z0-9_]*)/typeset \1/g'
    's/\${\([^}]*\)\^\^}/\${\1:u}/g'
)

for file in $files; do
    [[ $file == */modernize_zsh.sh ]] && continue

    printf "Processing: %s\n" "$file"

    # Check if file exists and is readable
    if [[ ! -f "$file" || ! -r "$file" ]]; then
        errors+=("$file: File not found or unreadable")
        exit 1
    fi

    # Handle symlinks by resolving to actual file
    if [[ -L "$file" ]]; then
        if ! resolved_file=$(readlink -f "$file" 2>/dev/null) || [[ ! -f "$resolved_file" ]]; then
            errors+=("$file: Symlink target not found or inaccessible")
            exit 1
        fi
        file="$resolved_file"
    fi

    # Create backup only if not already exists
    if [[ -f "${file}.bak" ]]; then
        printf "Backup already exists: %s\n" "${file}.bak"
    else
        if ! cp "$file" "${file}.bak"; then
            errors+=("$file: Backup failed")
            exit 1
        fi
    fi

    # Platform-specific sed in-place option
    typeset sed_in_place
    case $(uname) in
        Darwin) sed_in_place=(-i '') ;;
        *) sed_in_place=(-i) ;;
    esac

    # Test each pattern individually with dry run
    typeset pattern_failed=0
    for pattern in "${sed_patterns[@]}"; do
        if ! sed -n "${sed_in_place[@]}" -e "$pattern" -e 'q' "$file" >/dev/null 2>&1; then
            errors+=("$file: sed dry run failed for pattern: $pattern")
            exit 1
        fi
    done

    # Apply transformations one pattern at a time
    typeset apply_failed=0
    for pattern in "${sed_patterns[@]}"; do
        if ! sed "${sed_in_place[@]}" -e "$pattern" "$file"; then
            errors+=("$file: sed transformation failed for pattern: $pattern")
            rm -f "${file}.bak"
            exit 1
        fi
    done

    printf "Successfully modernized: %s\n" "$file"
    rm -f "${file}.bak"
done

printf "Total errors: %d\n" ${#errors}
exit ${#errors}
