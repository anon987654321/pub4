# Renders — committed sessions

Committed render records live here, one directory per session, named by the
seed that reproduces it. `dilla.rb` writes to `$PWD` by default, which is how
an earlier session left a whole render scattered across the repo root;
`DILLA_OUTPUT_DIR` overrides it, and this directory is where the artifacts
belong.

The split follows the repo-wide rule that no rendered audio is tracked. The
`.wav` files stay on disk and out of git — see the Engine output section of the
root `.gitignore` — while the record of the render is tracked: the `.dilla`
sidecars, the `quality.json` measurement, and the stem `motifs` and `session`
json. The sidecars record the absolute working directory of the machine that
rendered, which is provenance rather than a live path.

Reproduce from the `note` line in any sidecar:

    RENDER_SEED=1615715775 ruby STUDIO/dilla/dilla.rb loop.wav
