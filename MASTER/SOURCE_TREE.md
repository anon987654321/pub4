# Source Tree

Use this to distinguish source from generated or local-only state.

## Source

- `bin/`
- `lib/`
- `kernel/`
- `data/`
- `test/`
- `spec/`
- `tools/`
- `script/`
- `web/app/`
- `web/config/`
- `web/db/`
- `web/public/*.js`
- `web/public/*.css`
- `web/public/*.txt`
- `web/public/*.svg`

## Local Or Generated

- `.master/`
- `knowledge/`
- `output/`
- `runtime/`
- `web/log/`
- `web/tmp/`
- `web/storage/`
- `web/public/assets/`
- `web/public/packs/`

Do not include local/generated artifacts in ordinary patches unless the task explicitly targets them.
