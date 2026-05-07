# MASTER

A constitutional AI coding agent. Ruby. OpenBSD. Self-hosting.

MASTER reads its own constitution at boot, scans its own code for violation, sweeps the corruption, and argues the result through an adversarial council before shipping. It edits files. It does not narrate.

The pipeline runs in ten stages — Intake, Infer, Route, Guard, Execute, Council and Lint in parallel, Prune, Memo, Render. Every stage returns a Result monad. An axiom violation rolls the workspace back to HEAD. A thirty-second deadline binds the parallel pair.

The pipeline reads as two tanks. The Pressure tank compresses input — verbose user prose folded into a dense, intent-tagged prompt by Intake, Infer, and Compress. The Depressure tank refines output — Render applies smart quotes, em dashes, and ellipses outside code fences; the council and lint stages strip what the constitution would reject. Pressure favors signal density. Depressure favors typographic and axiomatic discipline. Together they bound every turn.

The constitution lives in `data/`. Thirty-six YAML files — soul, rules, ruby_style, workflow, standing_orders, models, council, council_questions, infer_patterns, sweep_prompts, zsh_patterns and the rest — replace the 1770-line monolith MASTER inherited and burned. The Ruby code reads these at boot. The agent is the config.

`rules.yml` carries six universal laws — Robustness, Singularity, Linearity, Proximity, Abstraction, Density — a single hierarchical ladder under which every named rule, persona, and fix verb is anchored. Lower number wins in conflict. Beside the laws sit a biases chapter (hallucination, simulation, sycophancy, completion theater, false confidence — meta-anti-patterns above lexical detection), a structural-ops vocabulary (merge, semantic regroup, defrag, decouple, hoist, flatten, delete, expand, reduce noise — each tagged with risk and verify spec), a veto-patterns table for regex-detected unconditional blocks (secrets, SQL injection, unfinished placeholders), and a beauty section that anchors aesthetic decisions to Bringhurst, Ando, Rams, and Martin. The voice paragraph carries Strunk & White safeguards — `apply_to: prose, comments, documentation, strings`; `never_apply_to: code logic, algorithms, data structures` — so refinement never silently deletes a variable name or collapses a conditional.

The scanner sweeps the tree in parallel across CPUs, applies fifty-plus named rules across four scopes — Prism-AST for Ruby structure, regex for anti-patterns, repo-graph mining for hidden coupling, registry self-checks for orphan rule files — and emits findings as data. The lexical layer covers structural smells (duplicate, god class, deep nesting, long method) and Rails-shaped hazards (n+1, mass assignment, time-zone unsafety, memoize-falsy, i18n leakage, stale TODO debt). The semantic layer runs an LLM conceptual pass that judges DRY, KISS, SOLID, POLA, and a mirror opportunity pass that names the pattern each file is 80% of the way to. The visual layer pushes every file toward the dominant silhouette — frozen-string-literal first, requires alphabetized, constants and attrs before init, `private` on its own line, one blank above each def, naming that matches return shape, and a structural fingerprint clustered against the rest of the directory. Two cross-file signals run beside the per-file rules: a co-change graph mined from the last five hundred commits flags pairs that always change together across module paths, and a comment-drift pass asks the LLM whether each comment still describes the code below it. Sweep takes the findings and rewrites the source — rubocop autocorrect first, deterministic and free; then the LLM, surgical and rate-limited, with best-of-N candidate scoring on files above four kilobytes; then the corruption guards reject anything that lost half its length, matched an error pattern, or failed `ruby -c`. Both `/scan` and `/sweep` default to deep depth, and `scan_since` accepts a git ref to scan only what changed.

Observability rides on a thin OpenTelemetry layer — `Master::Telemetry` wraps the event bus, metrics, audit log, and heartbeat in spans and emits JSONL traces to `.master/traces.log`. Soft-optional: if the gem is absent, every span call collapses to a plain yield.

The council convenes adversarial personas — pragmatist, purist, skeptic, historian — when a change touches a protection tier. Each speaks once. The pipeline waits, then ships or rolls back.

The voice is OpenBSD dmesg. Structured. Unhedged. Active. No headlines, no bullet lists without content, no apology. The forbidden words — *will*, *would*, *could*, *might* — surrender to the indicative.

Launch from the project root with `bundle exec ruby exe/master`. Pipe input through stdin for one-shot mode. The Rails 8 web face listens on 53187, fronted by relayd to ai.brgen.no — a 2000-particle orb, an ambient pad engine, seventeen voice effects, all incidental.

A live canvas — the openclaw inheritance — sits at `/canvas`. The agent draws nodes for violations, edges for fixes, a deliberation tree for council rounds, a timeline for sweep cycles. The user watches the constitution argue with the code in real time. Spec at `data/canvas.yml`, routes at `data/canvas_routes.yml`.

Deploy through `DEPLOY/openbsd/openbsd.sh`, two stages, resumable.

MIT.
