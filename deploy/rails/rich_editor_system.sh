```bash
# Tiptap (Medium-style) + stimulus-lightbox integration

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
    typeset app_name="${1:-current_app}"

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
}

create_tiptap_controller() {
    local controller_dir="app/javascript/controllers"
    local controller_file="$controller_dir/rich_editor_controller.js"

    if [[ ! -d "$controller_dir" ]]; then
        if ! mkdir -p "$controller_dir"; then
            error_exit "Failed to create controller directory: $controller_dir"
        fi
    fi

    cat > "$controller_file" << 'EOF'
import { Controller } from "@hotwired/stimulus"
import { Editor } from '@tiptap/core'
import StarterKit from '@tiptap/starter-kit'
import Link from '@tiptap/extension-link'
import Placeholder from '@tiptap/extension-placeholder'
import Underline from '@tiptap/extension-underline'
import Image from '@tiptap/extension-image'

export default class extends Controller {
    static targets = ["editor"]

    connect() {
        this.editor = new Editor({
            element: this.editorTarget,
            extensions: [
                StarterKit,
                Link.configure({
                    openOnClick: false,
                }),
                Placeholder.configure({
                    placeholder: 'Write something...',
                }),
                Underline,
                Image
            ],
            content: this.element.innerHTML,
            onUpdate: ({ editor }) => {
                this.element.innerHTML = editor.getHTML()
            }
        })
    }

    disconnect() {
        if (this.editor) {
            this.editor.destroy()
        }
    }
}
EOF

    if [[ ! -f "$controller_file" ]]; then
        error_exit "Failed to create controller file: $controller_file"
    fi
}

create_editor_styles() {
    local styles_dir="app/assets/stylesheets"
    local styles_file="$styles_dir/rich_editor.scss"

    if [[ ! -d "$styles_dir" ]]; then
        if ! mkdir -p "$styles_dir"; then
            error_exit "Failed to create styles directory: $styles_dir"
        fi
    fi

    cat > "$styles_file" << 'EOF'
.rich-editor {
    min-height: 200px;
    border: 1px solid #e0e0e0;
    border-radius: 4px;
    padding: 16px;

    .ProseMirror {
        outline: none;
        min-height: 150px;

        p.is-editor-empty:first-child::before {
            content: attr(data-placeholder);
            float: left;
            color: #adb5bd;
            pointer-events: none;
            height: 0;
        }

        a {
            color: #007bff;
            text-decoration: underline;
        }

        img {
            max-width: 100%;
            height: auto;
        }
    }

    .ProseMirror-focused {
        border-color: #007bff;
        box-shadow: 0 0 0 2px rgba(0, 123, 255, 0.25);
    }
}
EOF

    if [[ ! -f "$styles_file" ]]; then
        error_exit "Failed to create styles file: $styles_file"
    fi
}

setup_lightbox_integration() {
    local controller_dir="app/javascript/controllers"
    local lightbox_file="$controller_dir/lightbox_controller.js"

    if [[ ! -d "$controller_dir" ]]; then
        if ! mkdir -p "$controller_dir"; then
            error_exit "Failed to create controller directory: $controller_dir"
        fi
    fi

    cat > "$lightbox_file" << 'EOF'
import { Controller } from "@hotwired/stimulus"
import Lightbox from 'stimulus-lightbox'

export default class extends Lightbox {
    connect() {
        super.connect()
        console.log('Lightbox controller connected')
    }

    disconnect() {
        super.disconnect()
    }
}
EOF

    if [[ ! -f "$lightbox_file" ]]; then
        error_exit "Failed to create lightbox controller file: $lightbox_file"
    fi
}
```
