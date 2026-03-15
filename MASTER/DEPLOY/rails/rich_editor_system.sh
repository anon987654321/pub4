#!/usr/bin/env zsh
set -euo pipefail

log() {
  print -u2 -r -- "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

require_file() {
  [[ -f "$1" ]] || {
    log "Error: required file not found: $1"
    return 1
  }
}

install_tiptap_packages() {
  require_file package.json || return 1

  if command -v yarn >/dev/null 2>&1; then
    yarn add @tiptap/core @tiptap/starter-kit @tiptap/extension-link
  elif command -v npm >/dev/null 2>&1; then
    npm install --save @tiptap/core @tiptap/starter-kit @tiptap/extension-link
  else
    log "Error: neither yarn nor npm is available"
    return 1
  fi
}

create_tiptap_controller() {
  mkdir -p app/javascript/controllers
  cat > app/javascript/controllers/rich_text_controller.js <<'JS'
import { Controller } from "@hotwired/stimulus"
import { Editor } from "@tiptap/core"
import StarterKit from "@tiptap/starter-kit"
import Link from "@tiptap/extension-link"

export default class extends Controller {
  static targets = ["input", "editor"]

  connect() {
    this.editor = new Editor({
      element: this.editorTarget,
      extensions: [StarterKit, Link],
      content: this.inputTarget.value || "",
      onUpdate: ({ editor }) => {
        this.inputTarget.value = editor.getHTML()
      }
    })
  }

  disconnect() {
    if (this.editor) this.editor.destroy()
  }
}
JS
}

create_editor_styles() {
  mkdir -p app/assets/stylesheets
  cat > app/assets/stylesheets/rich_editor.css <<'CSS'
.rich-editor {
  border: 1px solid #d1d5db;
  border-radius: 12px;
  background: #ffffff;
  min-height: 14rem;
  padding: 0.875rem;
}

.rich-editor:focus-within {
  border-color: #2563eb;
  box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.2);
}
CSS
}

add_rich_editor() {
  local app_name="${1:-current_app}"
  log "Installing Tiptap rich editor into ${app_name}"

  install_tiptap_packages
  create_tiptap_controller
  create_editor_styles

  log "Rich editor scaffolding completed for ${app_name}"
}

if [[ "${(%):-%N}" == "$0" ]]; then
  add_rich_editor "${1:-current_app}"
fi
