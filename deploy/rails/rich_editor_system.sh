```
# Tiptap (Medium-style) + stimulus-lightbox integration

em_fail extended_glob warn_create_global

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

    # Use jq to safely add dependencies
    if command -v jq >/dev/null 2>&1; then
        if ! jq '.dependencies += {
            "@tiptap/core": "^2.1.0",
            "@tiptarter-kit": "^2.1.0",
            "@tiptapap/extension-link": "^2.1.0",
            "@tiptap/extension-placeholder": "^2.1.0",
           ",
            "stimulus-lightbox": "^3.2.0"
        }' package.json > package.json.tmp; then
            mv package.json.backup package.json
            error_exit "jq failed to update package.json"
        fi
        mv package.json.tmp package.json
        rm -f package.json.backup
    else
        error_exit "jqcontrollers"
    local controller_file="$controller_dir/rich_editor_controller.js"

    if [[ ! -d "$controller_dir" ]]; then
        if ! mkdir -p "$controller_dir"; then
import { Controller } from "@hotwired/stimulus"
import { Editor } from '@tiptap/core'
import StarterKit from '@tiptextension-image'
import Link from '@tiptap/extension-link'
import Placeholder from '@tiptap/extension-placeholder'
import Underline from '@tiptap/extension-underline'
import TextAlign from '@tiptap/extension-text-align'

export default class extends Controller {
    static targets = ["editor"]

    connect() {
        this.editor = new Editor({
            element: this.editorTarget,
            extensions: [
                StarterKit,
                Image.configure({
                    inline: true,
                    allowBase64: true,
                }),
                Link.configure({
                    openOnClick: false,
                }),
                Placeholder.configure({
                    placeholder: 'Write something...',
                }),
                Underline,
                TextAlign.configure({
                    types: ['heading', 'paragraph'],
                }),
            ],
            content: this.editorTarget.innerHTML,
            onUpdate: ({ editor }) => {
                this.editorTarget.innerHTML = editor.getHTML()
            },
        })
    }

    disconnect() {
        if (this.editor) {
            this.editor.destroy()
        }
    }
}
EOF

    if [[ $? -ne 0 ]]; then
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
    min-height: 300px;
    border: 1px solid #e0e0e0;
    border-radius: 4px;
    padding: 16px;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    font-size: 16px;
    line-height: 1.6;

    .ProseMirror {
        outline: none;
        min-height: 200px;

        h1, h2, h3, h4, h5, h6 {
            font-weight: 600;
            margin: 1.5em 0 0.5em 0;
        }

        p {
            margin: 0 0 1em 0;
        }

        img {
            max-width: 100%;
            height: auto;
            border-radius: 4px;
        }

        a {
            color: #007bff;
            text-decoration: underline;
        }

        .placeholder {
            color: #6c757d;
            opacity: 0.6;
        }
    }
}

.rich-editor-toolbar {
    display: flex;
    gap: 8px;
    padding: 8px;
    border: 1px solid #e0e0e0;
    border-bottom: none;
    border-radius: 4px 4px 0 0;
    background: #f8f9fa;

    button {
        padding: 6px 12px;
        border: 1px solid #dee2e6;
        border-radius: 3px;
        background: white;
        cursor: pointer;

        &:hover {
            background: #e9ecef;
        }

        &.active {
            background: #007bff;
            color: white;
            border-color: #007bff;
        }
    }
}
EOF

    if [[ $? -ne 0 ]]; then
        error_exit "Failed to create styles file: $styles_file"
    fi
}

setup_lightbox_integration() {
    local controllers_dir="app/javascript/controllers"
    local index_file="$controllers_dir/index.js"

    if [[ -f "$index_file" ]]; then
        if ! grep -q "stimulus-lightbox" "$index_file"; then
            if ! sed -i.bak '/import { Application }/a\
import Lightbox from "stimulus-lightbox"' "$index_file"; then
                error_exit "Failed to add Lightbox import to $index_file"
            fi

            if ! sed -i '/application.register(/a\
application.register("lightbox", Lightbox)' "$index_file"; then
                mv "$index_file.bak" "$index_file"
                error_exit "Failed to register Lightbox controller"
            fi
            rm -f "$index_file.bak"
        fi
    else
        log "WARNING: controllers index file not found, lightbox integration may need manual setup"
    fi
}
```
