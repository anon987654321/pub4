#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

#--- Configuration -----------------------------------------------------------
readonly RAILS_ROOT="${RAILS_ROOT:-$(pwd)}"
readonly GEMFILE="${RAILS_ROOT}/Gemfile"
readonly ROUTES_FILE="${ROUTES_FILE:-config/routes.rb}"
readonly STIMULUS_DIR="${STIMULUS_DIR:-app/javascript/controllers}"
readonly DRY_RUN="${DRY_RUN:-false}"

#--- Validation regex --------------------------------------------------------
readonly VALID_CLASS='^[A-Z][A-Za-z0-9]*$'
readonly VALID_CONTROLLER='^[A-Z][A-Za-z0-9]*Controller$'

#--- Helpers -----------------------------------------------------------------
die() {
    printf '%s\n' "$*" >&2
    exit 1
}

cmd_exists() {
    command -v "$1" >/dev/null 2>&1
}

usage() {
    cat <<-EOF
Usage: ${0##*/} [--dry-run] <ResourceName>

Generates a Rails model, controller and a Stimulus TypeScript controller.
  --dry-run    Show what would be done without making changes.
EOF
    exit 1
}

validate_rails_app() {
    [[ -f "$GEMFILE" ]] || die "Missing $GEMFILE – not a Rails project"
    grep -q "rails" "$GEMFILE" || die "Gemfile does not contain Rails"
    cmd_exists rails || die "rails executable not found"
}

validate_name() {
    local name=$1 pattern=$2 err=$3
    [[ $name =~ $pattern ]] || die "$err: $name"
}

to_snake_case() {
    printf '%s' "$1" |
        sed -E 's/([a-z0-9])([A-Z])/\1_\2/g' |
        tr '[:upper:]' '[:lower:]'
}

run_cmd() {
    local cmd=$1
    if $DRY_RUN; then
        printf '[dry‑run] %s\n' "$cmd"
    else
        eval "$cmd"
    fi
}

generate_model() {
    local model=$1
    validate_name "$model" "$VALID_CLASS" "Invalid model name"
    printf 'Generating model %s…\n' "$model"
    run_cmd "rails generate model $model"
    printf '✓ Model %s created\n' "$model"
}

generate_controller() {
    local controller=$1
    validate_name "$controller" "$VALID_CONTROLLER" "Invalid controller name"
    local base=${controller%Controller}
    printf 'Generating controller %s…\n' "$base"
    run_cmd "rails generate controller $base"
    printf '✓ Controller %s created\n' "$base"
}

generate_stimulus_ts() {
    local controller=$1
    validate_name "$controller" "$VALID_CONTROLLER" "Invalid controller name"
    local base=${controller%Controller}
    local snake
    snake=$(to_snake_case "$base")
    local file="${STIMULUS_DIR}/${snake}_controller.ts"

    if [[ -e $file ]]; then
        read -r -p "Stimulus file $file exists. Overwrite? (y/N) " reply
        [[ $reply =~ ^[Yy]$ ]] || { printf 'Skipping Stimulus generation\n'; return; }
    fi

    $DRY_RUN && { printf '[dry‑run] mkdir -p %s\n' "$STIMULUS_DIR"; printf '[dry‑run] create %s\n' "$file"; return; }

    mkdir -p "$STIMULUS_DIR"
    cat >"$file" <<'EOF'
import { Controller } from "@hotwired/stimulus"

export default class {{CLASS}} extends Controller {
  connect() {
    // Initialize controller logic here
  }
}
EOF
    # Replace placeholder with actual class name
    sed -i '' "s/{{CLASS}}/${controller}/g" "$file"
    printf '✓ Stimulus controller created: %s\n' "$file"
}

#--- Main --------------------------------------------------------------------
main() {
    local dry= false
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run) DRY_RUN=true; shift ;;
            -h|--help) usage ;;
            *) break ;;
        esac
    done

    local resource=${1:-}
    [[ -n $resource ]] || die "Usage: $0 <ResourceName>"
    validate_rails_app

    generate_model "$resource"
    generate_controller "${resource}Controller"
    generate_stimulus_ts "${resource}Controller"

    printf '\n✓ Resource generation completed successfully\n'
    printf 'Next steps:\n'
    printf '  • Run migrations: rails db:migrate\n'
    printf '  • Add routes to %s\n' "$ROUTES_FILE"
    printf '  • Implement controller actions and views\n'
}

#--- Entrypoint --------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi