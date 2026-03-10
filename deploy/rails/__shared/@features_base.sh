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

# Base generator functions
generate_model() {
    local model_name="$1"
    validate_rails_name "$model_name" || return 1

    if ! rails generate model "$model_name"; then
        echo "Error: Failed to generate model '$model_name'" >&2
        return 1
    fi
}

generate_controller() {
    local controller_name="$1"
    validate_controller_name "$controller_name" || return 1

    local base_name="${controller_name%Controller}"
    if ! rails generate controller "$base_name"; then
        echo "Error: Failed to generate controller '$base_name'" >&2
        return 1
    fi
}

generate_stimulus_ts() {
    local controller_name="$1"
    validate_controller_name "$controller_name" || return 1

    local base_name="${controller_name%Controller}"
    local stimulus_name=$(echo "$base_name" | perl -pe 's/(?<=[a-z])(?=[A-Z])/_/g' | tr '[:upper:]' '[:lower:]')
    local stimulus_file="${STIMULUS_DIR}/${stimulus_name}_controller.ts"

    if [[ -f "$stimulus_file" ]]; then
        read -p "Stimulus controller file '$stimulus_file' already exists. Overwrite? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Skipping Stimulus controller generation"
            return 0
        fi
    fi

    cat > "$stimulus_file" << EOF
import { Controller } from "@hotwired/stimulus"

export default class ${base_name}Controller extends Controller {
    connect() {
        // Initialization code here
    }
}
EOF

    echo "Generated Stimulus controller: $stimulus_file"
}
```
