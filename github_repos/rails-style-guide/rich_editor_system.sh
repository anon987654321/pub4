#!/usr/bin/env sh
set -euo pipefail

log() {
  printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$(basename "${0##*/}")" "$*" >&2
}

require_file() {
  if [ ! -f "$1" ]; then
    log "Error: required file not found: $1"
    return 1
  fi
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
  target="app/javascript/controllers/rich_text_controller.js"
  if [ -e "$target" ]; then
    log "Skipping controller creation; $target already exists"
    return 0
  fi

  mkdir -p "$(dirname "$target")"
  cat >"$target" <<'EOF'
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
    this.editor && this.editor.destroy()
  }
}
EOF
}

create_editor_styles() {
  target="app/assets/stylesheets/rich_editor.css"
  if [ -e "$target" ]; then
    log "Skipping stylesheet creation; $target already exists"
    return 0
  fi

  mkdir -p "$(dirname "$target")"
  cat >"$target" <<'EOF'
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
EOF
}

add_rich_editor() {
  app_name="${1:-$(basename "$(pwd)")}"
  log "Installing Tiptap rich editor into ${app_name}"
  install_tiptap_packages
  create_tiptap_controller
  create_editor_styles
  log "Rich editor scaffolding completed for ${app_name}"
}

# Execute only when run directly, not when sourced
case "$0" in
  *sh) add_rich_editor "${1:-}" ;;
esac
