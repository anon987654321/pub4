# postpro

Professional cinematic post-processing for stills — MASTER's image-grading
media tool. Entry point: `postpro/postpro.rb` (moved here from `tools/postpro.rb`
2026-07-18 so it has its own directory, alongside `repligen` and `dilla`).

## Run

```sh
ruby MASTER/tools/postpro/postpro.rb --input in.jpg --output out.jpg --preset portrait
```

Invoked programmatically through `Master::Io::ScriptDispatch` (tool name
`"postpro"`), which resolves either `tools/postpro.rb` or `tools/postpro/postpro.rb`
and runs it from the repo root. Natural-language routing goes through
`Io::MediaIntent` (`/postpro`); it is a slash-command tool, not an LLM-native
one (see `AGENTS.md`).

## Config

Reads `config.multimedia.postpro` from `master.json` (presets, defaults). If
`repligen` is present it composes with it (`repligen=active`).

## Callers

- `MASTER/web/app/services/image_presenter.rb` — web photo grading.
- Rails apps via `Pub4::DeployPaths#postpro_script` (newsletter heroes, TV
  thumbnails); see `RAILS` `Shared::NewsletterVisuals`, brgen `PostproJob`.

Move any future path references through `ScriptDispatch` / `DeployPaths` rather
than hardcoding the file location.
