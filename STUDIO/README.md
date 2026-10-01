# STUDIO

STUDIO owns the media-production implementations. MASTER remains the governance
runtime and exposes each tool through the canonical entrypoint pattern
`MASTER/tools/<tool>/<tool>.rb`; those paths are compatibility symlinks into
this tree.

postpro/postpro.rb — film emulation and image grading
replicate/replicate.rb — hosted image generation
lora/lora.rb — governed LoRA subject workflow dispatcher
dilla/dilla.rb — deterministic music generation and live playback
