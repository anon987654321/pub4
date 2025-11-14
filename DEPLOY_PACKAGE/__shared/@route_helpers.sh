#!/usr/bin/env zsh
set -euo pipefail

# Route helpers using pure zsh per master.json:stack:zsh_patterns
# No head/tail/sed/awk - pure parameter expansion

add_routes_block() {
    local routes_block="$1"

    local routes_file="config/routes.rb"

    local routes_lines=("${(@f)$(<$routes_file)}")
    {
        print -l "${routes_lines[1,-2]}"

        print -r -- "$routes_block"

        print "end"

    } > "$routes_file"

}

commit() {
    local message="${1:-Update application setup}"

    log "Committing changes: $message"
    if [ -d ".git" ]; then
        git add -A

        git commit -m "$message" || log "Nothing to commit"

    else

        log "Not a git repository, skipping commit"

    fi

}

