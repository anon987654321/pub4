#!/usr/bin/env zsh
# Rich Text Editor System
# Tiptap (Medium-style) + stimulus-lightbox integration

emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

add_rich_editor() {

  typeset app_name="${1:-current_app}"

  log "Adding Tiptap rich text editor to $app_name"

  install_tiptap_packages

  create_tiptap_controller

  create_editor_styles

  setup_lightbox_integration

  log "Rich text editor added to $app_name"

}

install_tiptap_packages() {

  cat >> package.json << 'EOF'

  "dependencies": {

    "@tiptap/core": "^2.1.0",

    "@tiptap/pm": "^2.1.0",

    "@tiptap/starter-kit": "^2.1.0",

    "@tiptap/extension-image": "^2.1.0",

    "@tiptap/extension-link": "^2.1.0",

    "@tiptap/extension-placeholder": "^2.1.0",

    "@tiptap/extension-underline": "^2.1.0",

    "@tiptap/extension-text-align": "^2.1.0",

    "stimulus-lightbox": "^3.2.0"

  }

EOF

  npm install

}

create_tiptap_controller() {

  cat > app/javascript/controllers/tiptap_controller.js << 'EOF'

import { Controller } from "@hotwired/stimulus"

import { Editor } from "@tiptap/core"

import StarterKit from "@tiptap/starter-kit"

import Image from "@tiptap/extension-image"

import Link from "@tiptap/extension-link"

import Placeholder from "@tiptap/extension-placeholder"

import Underline from "@tiptap/extension-underline"

import TextAlign from "@tiptap/extension-text-align"

export default class extends Controller {

  static targets = ["editor", "input"]

  static values = {

    placeholder: { type: String, default: "Write something..." },

    content: String

  }

  connect() {

    this.editor = new Editor({

      element: this.editorTarget,

      extensions: [

        StarterKit.configure({

          heading: { levels: [1, 2, 3] }

        }),

        Image.configure({

          inline: true,

          allowBase64: true

        }),

        Link.configure({

          openOnClick: false,

          HTMLAttributes: { class: 'tiptap-link' }

        }),

        Placeholder.configure({

          placeholder: this.placeholderValue

        }),

        Underline,

        TextAlign.configure({

          types: ['heading', 'paragraph']

        })

      ],

      content: this.contentValue || this.inputTarget.value,

      editorProps: {

        attributes: {

          class: 'tiptap-editor'

        }

      },

      onUpdate: ({ editor }) => {

        this.inputTarget.value = editor.getHTML()

      }

    })

    this.setupToolbar()

  }

  disconnect() {

    this.editor?.destroy()

  }

  setupToolbar() {

    const toolbar = this.element.querySelector('.editor-toolbar')

    if (!toolbar) return

    toolbar.querySelectorAll('[data-action]').forEach(btn => {

      btn.addEventListener('click', (e) => {

        e.preventDefault()

        const action = btn.dataset.action

        this.handleToolbarAction(action, btn)

      })

    })

  }

  handleToolbarAction(action, button) {

    const editor = this.editor

    const actions = {

      bold: () => editor.chain().focus().toggleBold().run(),

      italic: () => editor.chain().focus().toggleItalic().run(),

      underline: () => editor.chain().focus().toggleUnderline().run(),

      strike: () => editor.chain().focus().toggleStrike().run(),

      h1: () => editor.chain().focus().toggleHeading({ level: 1 }).run(),

      h2: () => editor.chain().focus().toggleHeading({ level: 2 }).run(),

      h3: () => editor.chain().focus().toggleHeading({ level: 3 }).run(),

      paragraph: () => editor.chain().focus().setParagraph().run(),

      bulletList: () => editor.chain().focus().toggleBulletList().run(),

      orderedList: () => editor.chain().focus().toggleOrderedList().run(),

      blockquote: () => editor.chain().focus().toggleBlockquote().run(),

      codeBlock: () => editor.chain().focus().toggleCodeBlock().run(),

      link: () => this.addLink(),

      image: () => this.addImage(),

      alignLeft: () => editor.chain().focus().setTextAlign('left').run(),

      alignCenter: () => editor.chain().focus().setTextAlign('center').run(),

      alignRight: () => editor.chain().focus().setTextAlign('right').run(),

      undo: () => editor.chain().focus().undo().run(),

      redo: () => editor.chain().focus().redo().run()

    }

    actions[action]?.()

    this.updateToolbarState()

  }

  addLink() {

    const url = prompt('Enter URL:')

    if (url) {

      this.editor.chain().focus()

        .extendMarkRange('link')

        .setLink({ href: url })

        .run()

    }

  }

  addImage() {

    const url = prompt('Enter image URL:')

    if (url) {

      this.editor.chain().focus().setImage({ src: url }).run()

    }

  }

  updateToolbarState() {

    const toolbar = this.element.querySelector('.editor-toolbar')

    if (!toolbar) return

    toolbar.querySelectorAll('[data-action]').forEach(btn => {

      const action = btn.dataset.action

      const isActive = this.editor.isActive(action)

      btn.classList.toggle('is-active', isActive)

    })

  }

}

EOF

}

create_editor_styles() {

  cat > app/assets/stylesheets/tiptap.css << 'EOF'

/* Tiptap Editor - Medium Style */

.tiptap-wrapper {

  max-width: 740px;

  margin: 0 auto;

  padding: 2rem 1rem;

}

.editor-toolbar {

  position: sticky;

  top: 0;

  background: white;

  border: 1px solid #e5e7eb;

  border-radius: 8px 8px 0 0;

  padding: 0.75rem;

  display: flex;

  gap: 0.25rem;

  flex-wrap: wrap;

  z-index: 10;

}

.editor-toolbar button {

  width: 32px;

  height: 32px;

  border: none;

  background: transparent;

  border-radius: 4px;

  cursor: pointer;

  color: #6b7280;

  transition: all 0.2s;

}

.editor-toolbar button:hover {

  background: #f3f4f6;

  color: #111827;

}

.editor-toolbar button.is-active {

  background: #e0e7ff;

  color: #4f46e5;

}

.tiptap-editor {

  min-height: 300px;

  max-width: 740px;

  margin: 0 auto;

  padding: 2rem;

  border: 1px solid #e5e7eb;

  border-top: none;

  border-radius: 0 0 8px 8px;

  background: white;

  font-family: Georgia, Cambria, "Times New Roman", Times, serif;

  font-size: 21px;

  line-height: 1.58;

  color: #1a1a1a;

  outline: none;

}

.tiptap-editor:focus {

  border-color: #d1d5db;

}

.tiptap-editor h1 {

  font-size: 42px;

  line-height: 1.2;

  font-weight: 700;

  margin: 2rem 0 1rem;

  letter-spacing: -0.022em;

}

.tiptap-editor h2 {

  font-size: 34px;

  line-height: 1.25;

  font-weight: 600;

  margin: 1.5rem 0 0.75rem;

  letter-spacing: -0.019em;

}

.tiptap-editor h3 {

  font-size: 26px;

  line-height: 1.3;

  font-weight: 600;

  margin: 1.25rem 0 0.5rem;

}

.tiptap-editor p {

  margin: 1rem 0;

}

.tiptap-editor a {

  color: inherit;

  text-decoration: underline;

  text-decoration-color: #d1d5db;

  transition: text-decoration-color 0.2s;

}

.tiptap-editor a:hover {

  text-decoration-color: #6b7280;

}

.tiptap-editor img {

  max-width: 100%;

  height: auto;

  border-radius: 4px;

  margin: 2rem auto;

  display: block;

}

.tiptap-editor blockquote {

  border-left: 3px solid #111827;

  padding-left: 1.5rem;

  margin: 1.5rem 0;

  font-style: italic;

  color: #6b7280;

}

.tiptap-editor code {

  background: #f3f4f6;

  padding: 0.2em 0.4em;

  border-radius: 3px;

  font-family: 'Monaco', 'Menlo', monospace;

  font-size: 0.85em;

}

.tiptap-editor pre {

  background: #1a1a1a;

  color: #f3f4f6;

  padding: 1rem;

  border-radius: 8px;

  overflow-x: auto;

  margin: 1.5rem 0;

}

.tiptap-editor pre code {

  background: none;

  padding: 0;

  color: inherit;

  font-size: 0.9em;

}

.tiptap-editor ul, .tiptap-editor ol {

  padding-left: 2rem;

  margin: 1rem 0;

}

.tiptap-editor li {

  margin: 0.5rem 0;

}

.tiptap-editor p.is-editor-empty:first-child::before {

  content: attr(data-placeholder);

  float: left;

  color: #adb5bd;

  pointer-events: none;

  height: 0;

}

@media (max-width: 768px) {

  .tiptap-editor {

    font-size: 18px;

    padding: 1rem;

  }

  .tiptap-editor h1 { font-size: 32px; }

  .tiptap-editor h2 { font-size: 26px; }

  .tiptap-editor h3 { font-size: 22px; }

}

EOF

}

setup_lightbox_integration() {

  cat > app/javascript/controllers/lightbox_controller.js << 'EOF'

import Lightbox from "stimulus-lightbox"

export default class extends Lightbox {

  connect() {

    super.connect()

    this.lightGallery.on('onAfterOpen', () => {

      console.log('Lightbox opened')

    })

  }

  get defaultOptions() {

    return {

      speed: 500,

      download: true,

      counter: true,

      thumbnail: true,

      fullScreen: true,

      zoom: true,

      share: false,

      autoplayFirstVideo: false,

      plugins: ['lgZoom', 'lgThumbnail', 'lgFullscreen']

    }

  }

}

EOF

  cat > app/assets/stylesheets/lightbox.css << 'EOF'

@import "lightgallery/css/lightgallery-bundle.css";

.lg-backdrop {

  background-color: rgba(0, 0, 0, 0.95);

}

.lg-toolbar {

  background: linear-gradient(to bottom, rgba(0,0,0,0.5), transparent);

}

.lg-thumb-outer {

  background-color: rgba(0, 0, 0, 0.9);

}

EOF

}

write_editor_partial() {

  mkdir -p app/views/shared

  cat > app/views/shared/_tiptap_editor.html.erb << 'EOF'

<div class="tiptap-wrapper"

     data-controller="tiptap"

     data-tiptap-placeholder-value="<%= placeholder %>"

     data-tiptap-content-value="<%= content %>">

  <div class="editor-toolbar">

    <button data-action="bold" title="Bold (⌘B)"><strong>B</strong></button>

    <button data-action="italic" title="Italic (⌘I)"><em>I</em></button>

    <button data-action="underline" title="Underline (⌘U)"><u>U</u></button>

    <button data-action="strike" title="Strikethrough">S</button>

    <div class="toolbar-separator"></div>

    <button data-action="h1" title="Heading 1">H1</button>

    <button data-action="h2" title="Heading 2">H2</button>

    <button data-action="h3" title="Heading 3">H3</button>

    <div class="toolbar-separator"></div>

    <button data-action="bulletList" title="Bullet List">•</button>

    <button data-action="orderedList" title="Ordered List">1.</button>

    <button data-action="blockquote" title="Quote">"</button>

    <button data-action="codeBlock" title="Code">&lt;/&gt;</button>

    <div class="toolbar-separator"></div>

    <button data-action="link" title="Insert Link">🔗</button>

    <button data-action="image" title="Insert Image">🖼️</button>

    <div class="toolbar-separator"></div>

    <button data-action="alignLeft" title="Align Left">⇤</button>

    <button data-action="alignCenter" title="Align Center">||</button>

    <button data-action="alignRight" title="Align Right">⇥</button>

    <div class="toolbar-separator"></div>

    <button data-action="undo" title="Undo (⌘Z)">↶</button>

    <button data-action="redo" title="Redo (⌘⇧Z)">↷</button>

  </div>

  <div data-tiptap-target="editor"></div>

  <%= hidden_field_tag name, content, data: { tiptap_target: "input" } %>

</div>

EOF

}

export -f add_rich_editor install_tiptap_packages create_tiptap_controller

export -f create_editor_styles setup_lightbox_integration write_editor_partial
