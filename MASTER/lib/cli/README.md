# MASTER/lib/cli

CLI REPL, turn pipeline, command registry, model routing, and script dispatch.

- `cli/` — REPL flow, command handlers, container wiring, result display
- `command_registry/` — slash commands and formatters
- `routing/` — model router, provider health, provider quarantine
- `stages/` — the turn's steps

`TurnRouter` runs six of the eight stages in this order: `infer` promotes a
natural-language message to a `:command` intent, `intake` parses it into intent
plus structured fields, `route` attaches the handler, `destructive_review` puts a
destructive command in front of the council, `execute` calls the handler, and
`render` formats the output.

The other two are not seats in that sequence. `enhance` is called as a class
method from `ChatController` and the CLI before the pipeline runs. `memory`
holds the patterns for durable user and project memories and voice episodes.

Entrypoints: `MASTER/bin/master`, `MASTER/bin/cli`, `bin/dogfood`.
