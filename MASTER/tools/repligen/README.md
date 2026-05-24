# repligen

MASTER-owned entrypoint for Replicate.com generation workflows.

The current implementation is still `DEPLOY/repligen.rb`; `MASTER/tools/repligen.rb` is the stable tool surface used by MASTER command dispatch and tool contracts.

## Run

```sh
ruby MASTER/tools/repligen.rb --help
ruby MASTER/tools/repligen.rb sync 100
ruby MASTER/tools/repligen.rb search upscale
ruby MASTER/tools/repligen.rb stats
```

Arguments are forwarded unchanged to the legacy implementation.

## Dependencies

- Ruby
- `sqlite3` gem
- `REPLICATE_API_TOKEN` or `~/.config/repligen/config.json`
- network access to Replicate

The legacy implementation may install missing gems and writes a local SQLite database.

## MASTER wiring

- Slash command: `/repligen ...`
- Tool contract: `repligen`
- Permission: `network`
- Side effects: network, filesystem, process

## Migration rule

Do not add new DEPLOY-facing call sites. New callers should use this MASTER entrypoint or the `/repligen` command.
