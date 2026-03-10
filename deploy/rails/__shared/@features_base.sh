```bash
#!/bin/bash

# Configuration
RAILS_ROOT="${RAILS_ROOT:-$(pwd)}"
ROUTES_FILE="${ROUTES_FILE:-config/routes.rb}"

# Validation functions
validate_rails_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[A-Z][a-zA-Z0-9]*$ ]]; then
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
        if ! validate_rails_name "$model"; then
            return 1
        fi
    done

    for model in "${models[@]}"; do
        if ! rails generate model "$model"; then
            echo "Error: Failed to generate model '$model'" >&2
            return 1
        fi
    done
}

generate_model_file() {
    local model_name="$1"
    if ! validate_rails_name "$model_name"; then
        return 1
    fi

    if ! rails generate model "$model_name"; then
        echo "Error: Failed to generate model '$model_name'" >&2
        return 1
    fi
}

generate_controller_file() {
    local controller_name="$1"
    if ! validate_rails_name "$controller_name"; then
        return 1
    fi

    if [[ ! "$controller_name" =~ Controller$ ]]; then
        echo "Error: '$controller_name' must end with 'Controller'" >&2
        return 1
    fi

    echo "Generating controller file for: $controller_name"
    if ! rails generate controller "$controller_name"; then
        echo "Error: Failed to generate controller '$controller_name'" >&2
        return 1
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
    local target_dir="${STIMULUS_DIR:-app/javascript/controllers}"

    if [[ ! -d "$target_dir" ]]; then
        mkdir -p "$target_dir" || {
            echo "Error: Failed to create directory '$target_dir'" >&2
            return 1
        }
    fi

    echo "Generating Stimulus TypeScript file for: $controller_name"
    local ts_file="${target_dir}/${snake_case_name}_controller.ts"

    cat > "$ts_file" << EOF
import { Controller } from "@hotwired/stimulus"

export default class ${controller_name} extends Controller {
    // Add your stimulus controller methods here
}
EOF

    if [[ $? -eq 0 ]]; then
        echo "Created Stimulus controller: $ts_file"
    else
        echo "Error: Failed to create Stimulus controller file" >&2
        return 1
    fi
}
```
