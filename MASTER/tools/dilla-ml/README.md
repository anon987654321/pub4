# dilla-ml (Tier B sidecar — stubs)

Optional ML pipeline adjacent to `dilla.rb`. The Ruby runtime ships heuristic
fallbacks in `lib/dilla_ml.rb` until these jobs are implemented offline.

| Job | Input | Output |
|-----|-------|--------|
| ddsp_regen | stems from `dilla.rb separate` | enhanced WAV |
| rave_latent | long render | `.latent` + interpolation script |
| mood_cluster | `samples/manifest.json` | tagged clusters |
| style_transfer | master WAV | vintage print WAV |

Set `DILLA_ML=1` to surface stub notes in `quality` JSON.