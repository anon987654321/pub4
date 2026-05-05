# MASTER

A constitutional AI coding agent. Ruby. OpenBSD. Self-hosting.

MASTER reads its own constitution at boot, scans its own code for violation, sweeps the corruption, and argues the result through an adversarial council before shipping. It edits files. It does not narrate.

The pipeline runs in ten stages — Intake, Infer, Route, Guard, Execute, Council and Lint in parallel, Prune, Memo, Render. Every stage returns a Result monad. An axiom violation rolls the workspace back to HEAD. A thirty-second deadline binds the parallel pair.

The constitution lives in `data/`. Eleven YAML files — soul, rules, ruby_style, workflow, standing_orders, models, council, infer_patterns, sweep_prompts, zsh_patterns, prompts — replace the 1770-line monolith MASTER inherited and burned. The Ruby code reads these at boot. The agent is the config.

The scanner sweeps the tree in parallel across CPUs, applies one hundred and fifty-four named rules across four scopes, and emits findings as data. Sweep takes those findings and rewrites the source — rubocop autocorrect first, deterministic and free; then the LLM, surgical and rate-limited; then the corruption guards reject anything that lost half its length, matched an error pattern, or failed `ruby -c`.

The council convenes adversarial personas — pragmatist, purist, skeptic, historian — when a change touches a protection tier. Each speaks once. The pipeline waits, then ships or rolls back.

The voice is OpenBSD dmesg. Structured. Unhedged. Active. No headlines, no bullet lists without content, no apology. The forbidden words — *will*, *would*, *could*, *might* — surrender to the indicative.

Launch from the project root with `bundle exec ruby exe/master`. Pipe input through stdin for one-shot mode. The Rails 8 web face listens on 53187, fronted by relayd to ai.brgen.no — a 2000-particle orb, an ambient pad engine, seventeen voice effects, all incidental.

Deploy through `DEPLOY/openbsd/openbsd.sh`, two stages, resumable.

MIT.
