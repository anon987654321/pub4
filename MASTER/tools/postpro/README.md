# postpro

Cinematic image post-processing. MASTER tool surface; implementation in `DEPLOY/postpro/postpro.rb`.

## Run

```sh
ruby MASTER/tools/postpro.rb --help
```

Forwards args to `DEPLOY/postpro/postpro.rb`.

## Dependencies

Ruby, libvips (`ruby-vips`), optional `tty-prompt`. May shell out for image ops — treat as side-effecting.

## Wiring

- CLI: `/postpro`
- Contract: `postpro` (permission: `exec`)

New callers use this entrypoint, not ad-hoc `DEPLOY/postpro.rb` paths.