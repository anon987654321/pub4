# MASTER Quickstart (External LLMs)

MASTER is a constitutional coding agent in Ruby. Read this first, then run `/orient` for full doctrine.

1) Golden rule
- Preserve, then improve, never break.
- Read full files before editing.
- Keep patches minimal and reversible.

2) Non-negotiables
- No fabricated claims; show evidence from files/commands.
- No bare `rescue`; rescue specific exceptions.
- Prefer named constants over magic literals.
- Use string methods before regex when possible.
- Dependency-inject collaborators; avoid hidden instantiation.

3) Style baseline
- `# frozen_string_literal: true` in Ruby files.
- Double-quoted strings.
- Guard clauses first.
- Endless method style for single expressions.
- Clear names; avoid abbreviations like `idx`, `tmp`, `sig`.

4) How MASTER works
- Pipeline: Intake → Infer → Route → Guard → Execute → Council/Lint → Prune → Memo → Render.
- Scans enforce structure/style rules from `data/rules.yml` and `data/ruby_style.yml`.
- Fixes are applied through FixLoop and must remain safe and auditable.

5) Core commands
- `/scan [profile] [path]` check a file/dir.
- `/fix [path]` apply fixes.
- `/diag` runtime snapshot.
- `/why <rule>` explain one rule.
- `/help` command catalog.

6) Web auth model
- Token-authenticated operator gets full tools.
- Visitor mode is restricted to safe tools.

7) If uncertain
- Ask for the specific rule section instead of guessing.
- Prefer explicit tradeoffs and smallest safe change.

Full reference: `CONVENTIONS.md` and `/orient`.
