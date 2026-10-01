# MASTER tools

`MASTER/tools/` is the stable compatibility and utility plane inside MASTER.

The four media implementations live canonically in `STUDIO/`:

- `dilla/dilla.rb` — music generation and playback
- `lora/lora.rb` — LoRA training workflows
- `postpro/postpro.rb` — image grading and processing
- `replicate/replicate.rb` — provider-backed image generation

The corresponding `MASTER/tools/{dilla,lora,postpro,replicate}` paths are compatibility
symlinks to STUDIO. Keep them working for existing callers, but do not add a second
physical implementation under MASTER/tools.

Other files in this directory are MASTER-owned operators, scanners, audits and
maintenance tools. Their source of truth remains here unless a tool is explicitly
moved to a governed subtree.

Use the tool's own README for implementation details. Do not turn this file into a
second tool manual; this page exists to explain the boundary and the compatibility
contract.
