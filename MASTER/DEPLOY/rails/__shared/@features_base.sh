```bash
#!/bin/bash

# Configuration
RAILS_ROOT="${RAILS_ROOT:-$(pwd)}"
ROUTES_FILE="${ROUTES_FILE:-config/routes.rb}"
STIMULUS_DIR="${STIMULUS_DIR:-app/javascript/controllers}"

# Exit on error and unset variables
set -euo pipefail

# Validation functions
validate_rails_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[A-Z][a-zA-Z]*$ ]]; then
        echo "Error: '$name' must be PascalCase and contain only letters" >&2
        return 1
    fi
    return 0
}

validate_controller_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[A-Z][a-zA-Z]*Controller$ ]]; then
        echo "Error: '$name' must be PascalCase and end with 'Controller'" >&2
        return 1
    fi
    return 0
}

validate_file_exists() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "Error: File '$file' does not exist" >&2
        return 1
    fi
    return 0
}

# Convert PascalCase to snake_case using bash built-ins
to_snake_case() {
    local name="$1"
    echo "$name" | sed -E 's/([a-z])([A-Z])/\1_\2/g' | tr '[:upper:]' '[:lower:]'
}

# Base generator functions
generate_model() {
    local model_name="$1"
    validate_rails_name "$model_name" || return 1

    echo "Generating model: $model_name"
    if rails generate model "$model_name"; then
        echo "✓ Successfully generated model: $model_name"
        return 0
    else
        echo "Error: Failed to generate model '$model_name'" >&2
        return 1
    fi
}

generate_controller() {
    local controller_name="$1"
    validate_controller_name "$controller_name" || return 1

    local base_name="${controller_name%Controller}"
    echo "Generating controller: $base_name"
    if rails generate controller "$base_name"; then
        echo "✓ Successfully generated controller: $base_name"
        return 0
    else
        echo "Error: Failed to generate controller '$base_name'" >&2
        return 1
    fi
}

generate_stimulus_ts() {
    local controller_name="$1"
    validate_controller_name "$controller_name" || return 1

    local base_name="${controller_name%Controller}"
    local stimulus_name=$(to_snake_case "$base_name")
    local stimulus_file="${STIMULUS_DIR}/${stimulus_name}_controller.ts"

    if [[ -f "$stimulus_file" ]]; then
        read -p "Stimulus controller '$stimulus_file' already exists. Overwrite? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Skipping Stimulus controller generation"
            return 0
        fi
    fi

    echo "Generating Stimulus controller: $stimulus_file"
    mkdir -p "$STIMULUS_DIR"

    cat > "$stimulus_file" << EOF
import { Controller } from "@hotwired/stimulus"

export default class ${controller_name} extends Controller {
    connect() {
        // Initialize controller logic here
    }
}
EOF

    if [[ -f "$stimulus_file" ]]; then
        echo "✓ Successfully generated Stimulus controller: $stimulus_file"
        return 0
    else
        echo "Error: Failed to generate Stimulus controller '$stimulus_file'" >&2
        return 1
    fi
}

# Main execution function
main() {
    local resource_name="$1"
    if [[ -z "$resource_name" ]]; then
        echo "Usage: $0 <ResourceName>" >&2
        exit 1
    fi

    echo "Starting resource generation for: $resource_name"
    echo "----------------------------------------"

    # Validate we're in a Rails application
    if [[ ! -f "Gemfile" ]] || ! grep -q "rails" "Gemfile"; then
        echo "Error: This doesn't appear to be a Rails application directory" >&2
        exit 1
    fi

    # Generate components with individual error handling
    local success=true

    if ! generate_model "$resource_name"; then
        success=false
    fi

    if ! generate_controller "${resource_name}Controller"; then
        success=false
    fi

    if ! generate_stimulus_ts "${resource_name}Controller"; then
        success=false
    fi

    echo "----------------------------------------"
    if [[ "$success" == true ]]; then
        echo "✓ Resource generation completed successfully"
        echo "Next steps:"
        echo "  - Run migrations: rails db:migrate"
        echo "  - Add routes to config/routes.rb"
        echo "  - Implement controller actions and views"
    else
        echo "⚠ Resource generation completed with errors"
        echo "Please review the output above and complete any missing steps manually"
        exit 1
    fi
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```
