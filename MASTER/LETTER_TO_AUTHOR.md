# Letter to the original author

Mischa,

I read MASTER as two systems living in one tree.

The first is the older operational organism: CLI, web, guards, loop control,
provider routing, telemetry, tests, and OpenBSD survival knowledge. The second
is the newer kernel: a small constitutional agent built around four ideas —
Kernel, Constitution, World, and Memory.

The kernel is the stronger idea. It is smaller, safer, and easier to reason
about. I therefore did not propose another broad subsystem. I promoted the
kernel into the spine that the rest of MASTER should eventually serve.

The main change is that every action now has to pass through the Constitution
before it can complete. The old kernel returned immediately on `done`, which
accidentally bypassed the evidence rule. That made the most important safety
law unenforced. I moved completion behind the constitutional gate.

I also changed command execution from shell strings to structured `argv`.
This is boring on purpose. Shell strings are hard to audit. Arrays are clear,
quotable, testable, and safe. MASTER should not trust clever quoting when it can
avoid the shell entirely.

Git handling also changed. The previous `commit -am` shape skipped untracked
files and treated every successful effect as commit-worthy. A write that
succeeds is not necessarily a verified patch. The new direction is explicit:
checkpoint, change, verify, stage, commit. Git becomes the audit log, not a
side effect.

Memory now records scored evidence instead of flipping a boolean after any
successful command. `true` is not proof. Passing tests, clean scans, review,
logs, and profiling have different weights. This matches the intent already
present in `rules.yml`.

I added `bin/master-kernel` as a safe executable entry point. It is deliberately
minimal. It proves the contract without giving a model ambient authority. The
old CLI remains untouched. This lets MASTER migrate instead of detonate.

I added `bin/status` because MASTER needs one compact health frame. Operators
should not have to reconstruct state from logs, git, env flags, and test output.

I updated packaging so the kernel is actually shipped, and I made preflight call
the real CI path instead of a stale hand-picked test list.

The strategic bet is this:

MASTER should not compete with AutoGPT, BabyAGI, or OpenClaw as a general agent.
It should beat them by narrowing its promise:

Given a Ruby/Rails/OpenBSD repo, observe it, change it safely, prove the change,
commit a reversible patch, and stop.

That is a better product. It is Unix-shaped. It is Rails-native. It is auditable.
It has fewer verbs, fewer escape hatches, and stronger failure behavior.

The next implementation step is to wrap the older MASTER systems as kernel
capabilities:

- filesystem
- git
- process
- tests
- Rails introspection
- OpenBSD service control
- web smoke checks
- provider routing

Each capability should declare its verbs, schema, timeout, rollback behavior,
blast radius, and evidence value. No ambient plugin power. No mystery skills.

This patch is intentionally conservative. It does not delete the old organism.
It gives it a spine.

— ChatGPT