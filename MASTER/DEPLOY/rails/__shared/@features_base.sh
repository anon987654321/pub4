#!/bin/bash
# frozen_string_literal: true

# Configuration
readonly RAILS_ROOT="${RAILS_ROOT:-$(pwd)}"
readonly ROUTES_FILE="${ROUTES_FILE:-config/routes.rb}"
readonly STIMULUS_DIR="${STIMULUS_DIR:-app/javascript/controllers}"
readonly GEMFILE="Gemfile"

# Regex patterns
readonly VALID_CLASS='^[A-Z][a-zA-Z]*$'
readonly VALID_CONTROLLER='^[A-Z][a-zA-Z]*Controller$'

# Error handling
die() {
    echo "$*" >&2
    exit 1
}

# Guard: ensure rails app root
validate_rails_app() {
    [[ -f "$GEMFILE" ]] || die "Missing $GEMFILE"
    grep -q "rails" "$GEMFILE" || die "Not a Rails application"
}

# Guard: validate resource name (PascalCase)
validate_resource_name() {
    local name="$1"
    [[ "$name" =~ $VALID_CLASS ]] || die "Invalid resource name: $name"
}

# Guard: validate controller name (PascalCase ending with Controller)
validate_controller_name() {
    local name="$1"
    [[ "$name" =~ $VALID_CONTROLLER ]] || die "Invalid controller name: $name"
}

# Convert PascalCase to snake_case
to_snake_case() {
    local name="$1"
    echo "$name" | sed -E 's/([a-z])([A-Z])/\1_\2/g' | tr '[:upper:]' '[:lower:]'
}

# Generate model
generate_model() {
    local model_name="$1"
    validate_resource_name "$model_name"

    echo "Generating model: $model_name"
    rails generate model "$model_name" || die "Failed to generate model $model_name"
    echo "✓ Model $model_name created"
}

# Generate controller
generate_controller() {
    local controller_name="$1"
    validate_controller_name "$controller_name"

    local base_name="${controller_name%Controller}"
    echo "Generating controller: $base_name"
    rails generate controller "$base_name" || die "Failed to generate controller $base_name"
    echo "✓ Controller $base_name created"
}

# Generate Stimulus controller
generate_stimulus_ts() {
    local controller_name="$1"
    validate_controller_name "$controller_name"

    local base_name="${controller_name%Controller}"
    local stimulus_name=$(to_snake_case "$base_name")
    local stimulus_file="${STIMULUS_DIR}/${stimulus_name}_controller.ts"

    [[ -f "$stimulus_file" ]] && {
        printf "Stimulus file %s exists. Overwrite? (y/N) " "$stimulus_file"
        read -r -n 1 reply
        echo
        [[ "$reply" =~ ^[Yy]$ ]] || { echo "Skipping Stimulus generation"; return 0; }
    }

    mkdir -p "$STIMULUS_DIR"
    cat > "$stimulus_file" <<'EOF'
import { Controller } from "@hotwired/stimulus"

export default class ${controller_name} extends Controller {
    connect() {
        // Initialize controller logic here
    }
}
EOF
    echo "✓ Stimulus controller created: $stimulus_file"
}

# Main execution
main() {
    local resource_name="${1:-}"
    [[ -z "$resource_name" ]] && die "Usage: $0 <ResourceName>"

    validate_rails_app

    generate_model "$resource_name"
    generate_controller "${resource_name}Controller"
    generate_stimulus_ts "${resource_name}Controller"

    printf "\n✓ Resource generation completed successfully\n"
    printf "Next steps:\n"
    printf "  - Run migrations: rails db:migrate\n"
    printf "  - Add routes to %s\n" "$ROUTES_FILE"
    printf "  - Implement controller actions and views\n"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi