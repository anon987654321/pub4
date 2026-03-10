

```bash#!/usr/bin/env bash

# Tiptaprich text editor integration script

# Logging function
log() {
    printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$1" >&2
}

# Error handling function
error_exit() {
    log "ERROR: $1"
    exit 1
}

add_rich_editor() {
    local app_name="${1:-current_app}"

    log "Adding Tiptap rich text editor to $app_name"

    install_tiptap_packages || error_exit "Failed to install packages"
    create_tiptap_controller || error_exit "Failed to create controller"
    create_editor_styles || error_exit "Failed to create styles"
    setup_lightbox_integration || error_exit "Failed to setup lightbox"

    log "Rich text editor added to $app_name"
}

install_tiptap_packages() {
    # Check if package.json exists
    if [[ ! -f package.json ]]; then
        error_exit "package.json not found in current directory"
    fi

    # Create backup
    cp package.json package.json.backup

    # Check if jq is available
    if ! command -v jq >/dev/null 2>&1; then
        error_exit "jq is required but not installed"
    fi

    # Use jq to safely add dependencies
    if ! jq '.dependencies += {
        "@tiptap/core": "^2.1.0",
        "@tiptap/starter-kit": "^2.1.0",
        "@tiptap/extension-link": "^2.1.0",
        "@tiptap/extension-placeholder": "^2.1.0",
        "@tiptap/extension-image": "^2.1.0",
        "stimulus-lightbox": "^3.2.0"
    }' package.json > package.json.tmp; then
        mv package.json.backup package.json
        error_exit "jq failed to update package.json"
    fi

    mv package.json.tmp package.json
    rm -f package.json.backup

    # Install packages
    if command -v yarn >/dev/null 2>&1; then
        yarn install || error_exit "yarn install failed"
    elif command -v npm >/dev/null 2>&1; then
        npm install || error_exit "npm install failed"
    else
        error_exit "No package manager (yarn or npm) found"
    fi
}

create_tiptap_controller() {
    local controller_dir="app/javascript/controllers"
    local controller_file="tiptap_controller.js"
    local controller_content="import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
    connect() {
        const editor = new Tiptap.Editor({
            extensions: [
                new StarterKit(),
                new Image(),
                new Placeholder(),
                new Link(),
            ],
            onUpdate: () => {
                this.element.value = editor.getHTML()
            },
        })

        this.element.addEventListener('input', () => {
            editor.updateHTML(this.element.value)
        })
    }
}"

    # Create controller directory if missing
    mkdir -p "$controller_dir" || error_exit "Failed to create controller directory"

    # Check if file exists and warn before overwriting
    if [[ -f "$controller_dir/$controller_file" ]]; then
        log "Warning: Overwriting existing controller file: $controller_dir/$controller_file"
    fi

    # Write controller file
    printf '%s' "$controller_content" > "$controller_dir/$controller_file" || error_exit "Failed to write controller file"
}

create_editor_styles() {
    local styles_dir="app/javascript/styles"
    local styles_file="tiptap.css"
    local styles_content=".tiptap-editor {
        min-height: 300px;
        border: 1px solid #ccc;
        padding: 10px;
    }"

    mkdir -p "$styles_dir" || error_exit "Failed to create styles directory"

    if [[ -f "$styles_dir/$styles_file" ]]; then
        log "Warning: Overwriting existing styles file: $styles_dir/$styles_file"
    fi

    printf '%s' "$styles_content" > "$styles_dir/$styles_file" || error_exit "Failed to write styles file"
}

setup_lightbox_integration() {
    local lightbox_dir="app/javascript/controllers"
    local lightbox_file="lightbox_controller.js"
    local lightbox_content="import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
    connect() {
        const lightbox = new Stimulus.Lightbox()
        lightbox.connect()
    }
}"

    mkdir -p "$lightbox_dir" || error_exit "Failed to create lightbox directory"

    if [[ -f "$lightbox_dir/$lightbox_file" ]]; then
        log "Warning: Overwriting existing lightbox controller: $lightbox_dir/$lightbox_file"
    fi

    printf '%s' "$lightbox_content" > "$lightbox_dir/$lightbox_file" || error_exit "Failed to write lightbox controller"
}
```
