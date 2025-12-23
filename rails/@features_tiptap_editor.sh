# Tiptap Rich Text Editor System
# Medium-inspired rich text editing for all Rails apps
# Usage: source @features_tiptap_editor.sh && add_tiptap_editor

add_tiptap_editor() {
  local app_name="${1:-current_app}"
  
  log "Adding Tiptap editor to $app_name"
  
  install_tiptap_packages
  create_tiptap_controller
  create_tiptap_component
  add_tiptap_styles
  
  log "Tiptap editor added successfully"
}

install_tiptap_packages() {
  log "Installing Tiptap packages..."
  
  cat >> package.json.tmp << 'EOF'
{
  "dependencies": {
    "@tiptap/core": "^2.1.13",
    "@tiptap/starter-kit": "^2.1.13",
    "@tiptap/extension-placeholder": "^2.1.13",
    "@tiptap/extension-link": "^2.1.13",
    "@tiptap/extension-image": "^2.1.13",
    "@tiptap/extension-youtube": "^2.1.13",
    "@tiptap/extension-mention": "^2.1.13",
    "@tiptap/extension-collaboration": "^2.1.13",
    "@tiptap/extension-collaboration-cursor": "^2.1.13"
  }
}
EOF
  
  npm install @tiptap/core @tiptap/starter-kit @tiptap/extension-placeholder \
    @tiptap/extension-link @tiptap/extension-image @tiptap/extension-youtube \
    @tiptap/extension-mention
  
  log "Tiptap packages installed"
}

create_tiptap_controller() {
  mkdir -p app/javascript/controllers
  
  cat > app/javascript/controllers/tiptap_controller.js << 'EOF'
import { Controller } from "@hotwired/stimulus"
import { Editor } from "@tiptap/core"
import StarterKit from "@tiptap/starter-kit"
import Placeholder from "@tiptap/extension-placeholder"
import Link from "@tiptap/extension-link"
import Image from "@tiptap/extension-image"

export default class extends Controller {
  static targets = ["editor", "input"]
  static values = {
    placeholder: { type: String, default: "Start writing..." },
    content: String,
    autosave: Boolean,
    autosaveUrl: String
  }
  
  connect() {
    this.initializeEditor()
    this.setupAutosave()
  }
  
  disconnect() {
    if (this.editor) {
      this.editor.destroy()
    }
    if (this.autosaveTimer) {
      clearTimeout(this.autosaveTimer)
    }
  }
  
  initializeEditor() {
    this.editor = new Editor({
      element: this.editorTarget,
      extensions: [
        StarterKit.configure({
          heading: { levels: [1, 2, 3] },
          bulletList: { HTMLAttributes: { class: 'list-disc ml-4' } },
          orderedList: { HTMLAttributes: { class: 'list-decimal ml-4' } }
        }),
        Placeholder.configure({
          placeholder: this.placeholderValue
        }),
        Link.configure({
          openOnClick: false,
          HTMLAttributes: { class: 'text-blue-600 underline' }
        }),
        Image.configure({
          HTMLAttributes: { class: 'max-w-full rounded' }
        })
      ],
      content: this.contentValue || '',
      onUpdate: ({ editor }) => {
        this.updateContent(editor)
      }
    })
  }
  
  updateContent(editor) {
    const html = editor.getHTML()
    const json = editor.getJSON()
    
    if (this.hasInputTarget) {
      this.inputTarget.value = html
    }
    
    if (this.autosaveValue) {
      this.scheduleAutosave(html)
    }
    
    this.dispatch('update', { detail: { html, json } })
  }
  
  setupAutosave() {
    if (!this.autosaveValue || !this.autosaveUrlValue) return
    
    this.autosaveDelay = 2000
  }
  
  scheduleAutosave(content) {
    clearTimeout(this.autosaveTimer)
    
    this.autosaveTimer = setTimeout(() => {
      this.performAutosave(content)
    }, this.autosaveDelay)
  }
  
  async performAutosave(content) {
    try {
      const response = await fetch(this.autosaveUrlValue, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.csrfToken
        },
        body: JSON.stringify({ content })
      })
      
      if (response.ok) {
        this.showAutosaveStatus('Saved')
      }
    } catch (error) {
      this.showAutosaveStatus('Error saving', true)
    }
  }
  
  showAutosaveStatus(message, isError = false) {
    this.dispatch('autosave', { 
      detail: { message, isError } 
    })
  }
  
  get csrfToken() {
    return document.querySelector('[name="csrf-token"]')?.content
  }
  
  bold() {
    this.editor.chain().focus().toggleBold().run()
  }
  
  italic() {
    this.editor.chain().focus().toggleItalic().run()
  }
  
  strike() {
    this.editor.chain().focus().toggleStrike().run()
  }
  
  code() {
    this.editor.chain().focus().toggleCode().run()
  }
  
  heading(event) {
    const level = parseInt(event.currentTarget.dataset.level)
    this.editor.chain().focus().toggleHeading({ level }).run()
  }
  
  bulletList() {
    this.editor.chain().focus().toggleBulletList().run()
  }
  
  orderedList() {
    this.editor.chain().focus().toggleOrderedList().run()
  }
  
  blockquote() {
    this.editor.chain().focus().toggleBlockquote().run()
  }
  
  codeBlock() {
    this.editor.chain().focus().toggleCodeBlock().run()
  }
  
  link() {
    const url = window.prompt('Enter URL:')
    
    if (url) {
      this.editor.chain().focus()
        .extendMarkRange('link')
        .setLink({ href: url })
        .run()
    }
  }
  
  unlink() {
    this.editor.chain().focus().unsetLink().run()
  }
  
  image() {
    const url = window.prompt('Enter image URL:')
    
    if (url) {
      this.editor.chain().focus().setImage({ src: url }).run()
    }
  }
  
  undo() {
    this.editor.chain().focus().undo().run()
  }
  
  redo() {
    this.editor.chain().focus().redo().run()
  }
  
  clear() {
    this.editor.chain().focus().clearContent().run()
  }
}
EOF
  
  log "Tiptap controller created"
}

create_tiptap_component() {
  mkdir -p app/components/tiptap
  
  cat > app/components/tiptap/editor_component.rb << 'EOF'
class Tiptap::EditorComponent < ViewComponent::Base
  def initialize(name:, content: nil, placeholder: "Start writing...", autosave: false, autosave_url: nil)
    @name = name
    @content = content
    @placeholder = placeholder
    @autosave = autosave
    @autosave_url = autosave_url
  end
  
  def editor_id
    "tiptap-editor-#{@name.parameterize}"
  end
end
EOF
  
  cat > app/components/tiptap/editor_component.html.erb << 'EOF'
<div class="tiptap-wrapper" 
     data-controller="tiptap"
     data-tiptap-placeholder-value="<%= @placeholder %>"
     data-tiptap-content-value="<%= @content %>"
     <%= "data-tiptap-autosave-value='true'" if @autosave %>
     <%= "data-tiptap-autosave-url-value='#{@autosave_url}'" if @autosave_url %>>
  
  <div class="tiptap-menubar">
    <div class="menubar-group">
      <button type="button" 
              data-action="click->tiptap#bold" 
              class="menubar-button"
              title="Bold (Ctrl+B)">
        <strong>B</strong>
      </button>
      
      <button type="button" 
              data-action="click->tiptap#italic" 
              class="menubar-button"
              title="Italic (Ctrl+I)">
        <em>I</em>
      </button>
      
      <button type="button" 
              data-action="click->tiptap#strike" 
              class="menubar-button"
              title="Strikethrough">
        <s>S</s>
      </button>
      
      <button type="button" 
              data-action="click->tiptap#code" 
              class="menubar-button"
              title="Code">
        &lt;/&gt;
      </button>
    </div>
    
    <div class="menubar-divider"></div>
    
    <div class="menubar-group">
      <button type="button" 
              data-action="click->tiptap#heading" 
              data-level="1"
              class="menubar-button"
              title="Heading 1">
        H1
      </button>
      
      <button type="button" 
              data-action="click->tiptap#heading" 
              data-level="2"
              class="menubar-button"
              title="Heading 2">
        H2
      </button>
      
      <button type="button" 
              data-action="click->tiptap#heading" 
              data-level="3"
              class="menubar-button"
              title="Heading 3">
        H3
      </button>
    </div>
    
    <div class="menubar-divider"></div>
    
    <div class="menubar-group">
      <button type="button" 
              data-action="click->tiptap#bulletList" 
              class="menubar-button"
              title="Bullet List">
        •
      </button>
      
      <button type="button" 
              data-action="click->tiptap#orderedList" 
              class="menubar-button"
              title="Numbered List">
        1.
      </button>
      
      <button type="button" 
              data-action="click->tiptap#blockquote" 
              class="menubar-button"
              title="Quote">
        "
      </button>
    </div>
    
    <div class="menubar-divider"></div>
    
    <div class="menubar-group">
      <button type="button" 
              data-action="click->tiptap#link" 
              class="menubar-button"
              title="Add Link">
        🔗
      </button>
      
      <button type="button" 
              data-action="click->tiptap#image" 
              class="menubar-button"
              title="Add Image">
        🖼️
      </button>
    </div>
    
    <div class="menubar-divider"></div>
    
    <div class="menubar-group">
      <button type="button" 
              data-action="click->tiptap#undo" 
              class="menubar-button"
              title="Undo">
        ↶
      </button>
      
      <button type="button" 
              data-action="click->tiptap#redo" 
              class="menubar-button"
              title="Redo">
        ↷
      </button>
    </div>
  </div>
  
  <div class="tiptap-editor" 
       data-tiptap-target="editor"
       id="<%= editor_id %>"></div>
  
  <input type="hidden" 
         name="<%= @name %>" 
         data-tiptap-target="input">
  
  <% if @autosave %>
    <div class="tiptap-status" data-tiptap-target="status"></div>
  <% end %>
</div>
EOF
  
  log "Tiptap component created"
}

add_tiptap_styles() {
  mkdir -p app/assets/stylesheets
  
  cat > app/assets/stylesheets/tiptap.css << 'EOF'
.tiptap-wrapper {
  border: 1px solid #e5e7eb;
  border-radius: 8px;
  overflow: hidden;
  background: white;
}

.tiptap-menubar {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 8px;
  border-bottom: 1px solid #e5e7eb;
  background: #f9fafb;
  flex-wrap: wrap;
}

.menubar-group {
  display: flex;
  gap: 2px;
}

.menubar-divider {
  width: 1px;
  height: 24px;
  background: #e5e7eb;
  margin: 0 4px;
}

.menubar-button {
  min-width: 32px;
  height: 32px;
  padding: 0 8px;
  border: none;
  background: transparent;
  border-radius: 4px;
  cursor: pointer;
  font-size: 14px;
  color: #374151;
  transition: all 0.2s;
  display: flex;
  align-items: center;
  justify-content: center;
}

.menubar-button:hover {
  background: #e5e7eb;
}

.menubar-button.is-active {
  background: #dbeafe;
  color: #1e40af;
}

.tiptap-editor {
  min-height: 200px;
  padding: 16px;
  font-size: 16px;
  line-height: 1.6;
}

.tiptap-editor:focus {
  outline: none;
}

.tiptap-editor .ProseMirror {
  min-height: 180px;
}

.tiptap-editor h1 {
  font-size: 2em;
  font-weight: 700;
  margin-bottom: 0.5em;
}

.tiptap-editor h2 {
  font-size: 1.5em;
  font-weight: 600;
  margin-bottom: 0.5em;
}

.tiptap-editor h3 {
  font-size: 1.25em;
  font-weight: 600;
  margin-bottom: 0.5em;
}

.tiptap-editor p {
  margin-bottom: 1em;
}

.tiptap-editor ul,
.tiptap-editor ol {
  margin-bottom: 1em;
  padding-left: 1.5em;
}

.tiptap-editor blockquote {
  border-left: 4px solid #e5e7eb;
  padding-left: 1em;
  margin: 1em 0;
  font-style: italic;
  color: #6b7280;
}

.tiptap-editor code {
  background: #f3f4f6;
  padding: 2px 6px;
  border-radius: 4px;
  font-family: 'Monaco', 'Courier New', monospace;
  font-size: 0.9em;
}

.tiptap-editor pre {
  background: #1f2937;
  color: #f9fafb;
  padding: 1em;
  border-radius: 8px;
  overflow-x: auto;
  margin: 1em 0;
}

.tiptap-editor pre code {
  background: transparent;
  padding: 0;
  color: inherit;
}

.tiptap-editor img {
  max-width: 100%;
  height: auto;
  border-radius: 8px;
  margin: 1em 0;
}

.tiptap-editor .is-empty::before {
  content: attr(data-placeholder);
  color: #9ca3af;
  pointer-events: none;
  height: 0;
  float: left;
}

.tiptap-status {
  padding: 8px 16px;
  font-size: 12px;
  color: #6b7280;
  border-top: 1px solid #e5e7eb;
  background: #f9fafb;
}

.tiptap-status.saved {
  color: #059669;
}

.tiptap-status.error {
  color: #dc2626;
}

@media (max-width: 640px) {
  .tiptap-menubar {
    padding: 4px;
  }
  
  .menubar-button {
    min-width: 28px;
    height: 28px;
    font-size: 12px;
  }
  
  .tiptap-editor {
    padding: 12px;
    font-size: 14px;
  }
}
EOF
  
  log "Tiptap styles added"
}

create_tiptap_helper() {
  cat > app/helpers/tiptap_helper.rb << 'EOF'
module TiptapHelper
  def tiptap_editor(name, content: nil, **options)
    render Tiptap::EditorComponent.new(
      name: name,
      content: content,
      **options
    )
  end
end
EOF
  
  log "Tiptap helper created"
}

export -f add_tiptap_editor install_tiptap_packages create_tiptap_controller
export -f create_tiptap_component add_tiptap_styles create_tiptap_helper
