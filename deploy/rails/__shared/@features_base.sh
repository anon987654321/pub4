#!/bin/bash

# Configuration
RAILS_ROOT="${RAILS_ROOT:-$(pwd)}"
ROUTES_FILE="${ROUTES_FILE:-config/routes.rb}"

# Validation functions
validate_rails_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[A-Z][A-Za-z0-9]*$ ]]; then
        echo "Error: '$name' must be PascalCase and start with uppercase letter" >&2
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
generate_models() {
    local models=("$@")
    for model in "${models[@]}"; do
        if validate_rails_name "$model"; then
            rails generate model "$model"
        fi
    done
}

generate_model_file() {
    local model_name="$1"
    if validate_rails_name "$model_name"; then
        rails generate model "$model_name"
    fi
}

generate_controller_file() {
    local controller_name="$1"
    if validate_rails_name "$controller_name"; then
        echo "Generating controller file for: $controller_name"
        rails generate controller "$controller_name"
    fi
}

generate_stimulus_ts() {
    local controller_name="$1"
    if ! validate_rails_name "$controller_name"; then
        return 1
    fi

    if [[ ! "$controller_name" =~ Controller$ ]]; then
        echo "Error: '$controller_name' must end with 'Controller'" >&2
        return 1
    fi

    local snake_case_name=$(echo "$controller_name" | sed 's/Controller$//' | sed 's/\([a-z0-9]\)\([A-Z]\)/\1_\2/g' | tr '[:upper:]' '[:lower:]')
    local target_dir="app/javascript/controllers"

    if [[ ! -d "$target_dir" ]]; then
        mkdir -p "$target_dir" || {
            echo "Error: Failed to create directory '$target_dir'" >&2
            return 1
        }
    fi

    echo "Generating Stimulus TypeScript file for: $controller_name"
    cat > "$target_dir/${snake_case_name}_controller.ts" << EOF
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {}
}
EOF
}

# Usage
if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <command> [arguments...]" >&2
    echo "Available commands: generate-models, generate-controller, generate-stimulus-ts" >&2
    exit 1
fi

case "$1" in
    generate-models)
        shift
        generate_models "$@"
        ;;
    generate-controller)
        shift
        generate_controller_file "$1"
        ;;
    generate-stimulus-ts)
        shift
        generate_stimulus_ts "$1"
        ;;
    *)
        echo "Unknown command: $1" >&2
        exit 1
        ;;
esac
