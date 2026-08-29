# CLI

**Every sentence a person types at MASTER becomes a turn, and this is the machine
that runs one.** The REPL, the turn pipeline, the command registry, model routing,
and script dispatch all live here.

`cli/` is the REPL flow, the command handlers, the container wiring, and the
result display. `command_registry/` holds the slash commands and their
formatters. `routing/` is the model router with provider health and quarantine.
`stages/` is the turn's steps.

`TurnRouter` runs six of the eight stages, in order. `infer` promotes a
natural-language message to a `:command` intent. `intake` parses it into an
intent plus structured fields. `route` attaches the handler. `destructive_review`
puts a destructive command in front of the council. `execute` calls the handler,
and `render` formats what comes back.

The other two are not seats in that sequence, which is the thing to know before
you go looking for them there. `ChatController` and the CLI both call `enhance`
as a class method before the pipeline runs at all, and `memory` holds the
patterns for durable user and project memories and for voice episodes.

Enter through `MASTER/bin/master`, `MASTER/bin/cli`, or `bin/dogfood`.
