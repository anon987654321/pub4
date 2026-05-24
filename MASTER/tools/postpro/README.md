# postpro

MASTER-owned entrypoint for cinematic image post-processing.

The current processing implementation is still `DEPLOY/postpro.rb`; `MASTER/tools/postpro.rb` is the stable tool surface used by MASTER command dispatch and tool contracts.

## Run

```sh
ruby MASTER/tools/postpro.rb --help
```

Arguments are forwarded unchanged to the legacy implementation.

## Dependencies

- Ruby
- libvips / `ruby-vips`
- optional `tty-prompt`

The legacy implementation may attempt to install missing gems or system packages. Treat this as an executable side-effecting tool.

## MASTER wiring

- Slash command: `/postpro ...`
- Tool contract: `postpro`
- Permission: `exec`
- Side effects: filesystem, process

## Migration rule

Do not add new DEPLOY-facing call sites. New callers should use this MASTER entrypoint or the `/postpro` command.
