# Cleanup and Trace Playbook

## Goal

MASTER should be:

- replayable
- inspectable
- resumable
- grepable
- deterministic at orchestration level
- explicit about failures

Cleanup and trace are not optional maintenance. They are runtime law.

## Cleanup targets

Delete or collapse:

- stale namespaces
- duplicate registries
- shadow documentation
- hidden mutable globals
- silent retries
- direct provider calls
- direct tool side effects
- UI/runtime coupling
- duplicate telemetry paths
- narrative-only recovery logic

## Mandatory post-refactor checks

Run:

```sh
bundle exec ruby exe/master-smoke
bundle exec rubocop
bundle exec reek
bundle exec flay lib
```

Then:

- inspect runtime/events
- inspect runtime/telemetry
- inspect replay/checkpoints
- inspect provider routing
- inspect namespace audit output

## Trace doctrine

Every irreversible action must emit:

```text
before_event
execution
after_event
verification
telemetry
repair_ticket_on_failure
```

Missing events are runtime corruption.

## Debug doctrine

Do not trust:

- summaries
- assumptions
- inferred state
- UI appearance
- model narration

Trust:

- runtime events
- telemetry
- checkpoints
- explicit verification
- replay reconstruction

## OpenBSD influence

Logs should resemble dmesg:

- terse
- timestamped
- subsystem-prefixed
- stable ordering
- grepable
- operationally meaningful

Avoid:

- emoji logs
- spinner spam
- decorative narration
- fake progress
- hype language

## Runtime observability

Visual state must derive from:

- runtime events
- provider telemetry
- workflow topology
- repair state
- replay state

Not from guessed frontend state.

## Final rule

If the runtime cannot explain:

- what happened
- why it happened
- what mutated
- what failed
- how to replay it

then the runtime is incomplete.
