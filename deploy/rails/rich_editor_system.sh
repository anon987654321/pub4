

```bash
#!/usr/bin/env bash

# Tiptap rich text editor integration script

# Logging function
log() {
    printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$1" >&2
}

# Error handling function
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Cleanup function for rollback
cleanup() {
    if [[ -f package.json.backup ]]; then
        mv package.json.backup package.json
        log "Rolled back package.json changes"
    fi
    if [[ -f package.json.tmp ]]; then
        rm -f package.json.tmp
    fi
}

add_rich_editor() {
    local app_name="${1:-current_app}"
    local success_steps=0
    local total_steps=4

    log "Adding Tiptap rich text editor to $app_name"

    # Setup cleanup trap
    trap cleanup EXIT

    install_tiptap_packages && ((success_steps++)) || error_exit "Failed to install packages"
    create_tiptap_controller && ((success_steps++)) || error_exit "Failed to create controller"
    create_editor_styles && ((success_steps++)) || error_exit "Failed to create styles"
    setup_lightbox_integration && ((success_steps++)) || error_exit "Failed to setup lightbox"

    # Remove cleanup trap on success
    trap - EXIT

    if [[ $success_steps -eq $total_steps ]]; then
        log "Rich text editor successfully added to $app_name"
    else
        error_exit "Partial installation completed ($success_steps/$total_steps steps). Rolled back changes."
    fi
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

    # Validate JSON structure first
    if ! jq empty package.json >/dev/null 2>&1; then
        error_exit "package.json contains invalid JSON"
    fi

    # Use jq to safely add dependencies
    if ! jq '.dependencies += {
        "@tiptap/core": "^1.0.0",
        "@tiptap/react": "^1.0.0",
        "@tiptap/pm": "^1.0.0",
        "@tiptap/pm-mention": "^1.0.0",
        "@tiptap/pm-table": "^1.0.0",
        "@tiptap/pm-emoji": "^1.0.0",
        "@tiptap/pm-image": "^1.0.0",
        "@tiptap/pm-file": "^1.0.0",
        "@tiptap/pm-emoji": "^1.0.0",
        "@tiptap/pm-emoji": "^1.0.0"
    }' package.json > package.json.tmp; then
        error_exit "Failed to update package.json dependencies"
    fi

    # Remove backup since update succeeded
    rm -f package.json.backup
}

create_tiptap_controller() {
    local controller_path="src/controllers/tiptap.controller.js"
    cat > "$controller_path" << 'EOF'
import { Editor } from '@tiptap/core'
import { ReactEditor } from '@tiptap/react'
import { InputRule } from '@tiptap/pm/inputrule'
import { MentionPlugin } from '@tiptap/pm/mention'
import { TablePlugin } from '@tiptap/pm/table'
import { EmojiPlugin } from '@tiptap/pm/emoji'
import { ImagePlugin } from '@tiptap/pm/image'
import { FilePlugin } from '@tiptap/pm/file'
import { Mention } from '@tiptap/pm/mention'
import { Table } from '@tiptap/pm/table'
import { Emoji } from '@tiptap/pm/emoji'
import { Image } from '@tiptap/pm/image'
import { File } from '@tiptap/pm/file'

const editor = new Editor({
    extensions: [
        new ReactEditor(),
        new MentionPlugin({
            mention: {
                async getSuggestions(query) {
                    return await fetch(`/api/mentions?q=${query}`).then(res => res.json())
                }
            }
        }),
        new TablePlugin(),
        new EmojiPlugin(),
        new ImagePlugin(),
        new FilePlugin(),
    ],
    content: '',
    onUpdate: () => {
        console.log('Editor content changed')
    }
})

export default editor
EOF
    if [[ ! -f "$controller_path" ]]; then
        error_exit "Failed to create controller file at $controller_path"
    fi
}

create_editor_styles() {
    local styles_path="src/styles/editor.css"
    cat > "$styles_path" << 'EOF'
.tiptap-editor {
    min-height: 300px;
    padding: 20px;
    border: 1px solid #ddd;
    border-radius: 4px;
    background-color: #fff;
}

.tiptap-editor .tiptap-root {
    min-height: 200px;
}
EOF
    if [[ ! -f "$styles_path" ]]; then
        error_exit "Failed to create styles file at $styles_path"
    fi
}

setup_lightbox_integration() {
    local lightbox_path="src/components/EditorLightbox.jsx"
    cat > "$lightbox_path" << 'EOF'
import React from 'react'
import { Editor } from '@tiptap/react'

const EditorLightbox = () => {
    return (
        <div className="lightbox">
            <Editor />
        </div>
    )
}

export default EditorLightbox
EOF
    if [[ ! -f "$lightbox_path" ]]; then
        error_exit "Failed to create lightbox file at $lightbox_path"
    fi
}
```
