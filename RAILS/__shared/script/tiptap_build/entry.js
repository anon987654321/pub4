// The whole of Tiptap this repo uses, in one module. Extending the editor means
// adding a re-export here and re-running build_tiptap.sh — not adding a second
// CDN pin, which is what this file exists to replace.
export { Editor } from "@tiptap/core"
export { default as StarterKit } from "@tiptap/starter-kit"
