# CANON

The single authoritative directory of MASTER's rule corpus. Read this first,
every session, before touching code. It does not copy rules — copying would
violate ONE_SOURCE. It locates them: every source, where it lives, what it
governs. When a rule's text is needed, open the file named here.

## Working contract — reinforce before every task

1. Read this file. Then read the source for the rules the task touches.
2. PRESERVE_THEN_IMPROVE_NEVER_BREAK is the golden rule. It outranks every
   other instruction, including a user's request to move fast.
3. TEST_FIRST is an axiom: if you cannot test a change, you cannot ship it.
   State plainly when the suite cannot run; never claim a result you did
   not observe.
4. ONE_CHANGE: one logical change per commit, verified before the next.
5. SELF_APPLY: code you write is held to the same rules it enforces.
6. data/ is a sacred path (ABSOLUTE tier). Edits there are deliberate.

## Layer 1 — the constitution (machine-readable, loaded at runtime)

- data/axioms.jsonl — 41 engineering, structural, and process axioms. One
  JSON object per line: name, description, category. The spine.
- data/soul.yml — ABSOLUTE section: golden_rule, sacred_paths,
  anti_simulation, protection_tiers, code_rules, aesthetic_rules.
- data/rules.yml — 76 scan rules with per-rule detection axes and
  thresholds; the thresholds: block holds only values with a live reader.
- data/rule_deps.yml — topological ordering for the scan rules.
- data/style.yml — Ruby-specific style: quoting, frozen_string,
  comment limits, whitespace.
- data/epistemics.yml — confidence and evidence rules.
- data/workflow.yml — pipeline stage rules.

## Layer 2 — operator principles (data/principles/*.md, 32 files)

Operator-declared feedback, loaded by lib/ground/constitution.rb. Each
overrides defaults. Grouped by what they govern:

- Process: autofix, autoproceed, continue_backlog, decisive_signals,
  git_commits, no_new_files, no_permission_questions, readme_autoupdate,
  run_through_master_triad, restart_rails, diverged_branch_sync.
- Code style: importance_order, lint_beautify, comments_reassess, style,
  micro_refinements, no_consecutive_whitespace, no_useless_knobs.
- Voice and prose: strunk_white, voice_terse_unix, proper_casing,
  meta_framing, master_prompt_aesthetic.
- Medium and tooling: no_python, no_sed, no_shell_piping,
  master_zsh_discipline, html_css_style, device_limits.
- Cross-cutting: universal_cross_disciplinary_rules — every rule is a
  medium-agnostic principle with per-medium adapters.
- Design: flat_pixels, motion_color_grading.

## Layer 3 — external canon (the lineages the rules descend from)

These are not files in this repo. They are the philosophical sources the
axioms operationalize. When a rule's intent is unclear, the lineage is the
reference. Each line: the source, then where MASTER applies it.

- KISS, YAGNI, Occam's Razor — SIMPLEST_WORKS, JUST_ENOUGH (axioms.jsonl).
- DRY — ONE_SOURCE, MERGE (axioms.jsonl).
- SOLID — ONE_JOB, EXTEND_DONT_MODIFY, SUBSTITUTABLE, SMALL_INTERFACES,
  DEPEND_ON_ABSTRACTIONS (axioms.jsonl).
- POLA, principle of least astonishment — NO_SURPRISES, USER_FRIENDLY.
- Structural operations: defrag, decouple, flatten, hoist, prune, coalesce,
  reflow — the structural axioms in axioms.jsonl, ordered by rule_deps.yml.
- Recomment, reorganize, rename, rephrase — comments_reassess,
  importance_order, SELF_EXPLAINING.
- Strunk & White, The Elements of Style — principles/feedback_strunk_white.
- NN/g (Nielsen Norman) usability heuristics — USER_FRIENDLY,
  VISUAL_HIERARCHY, NO_DEAD_ENDS.
- The Pragmatic Programmer — LEAVE_BETTER, REVERSIBLE, ONE_CHANGE,
  orthogonality, tracer bullets, broken-windows.
- Clean Code / Refactoring (Martin, Fowler) — the ZEN_METHOD thresholds in
  rules.yml; method and class size limits.
- Polished Ruby Programming (Evans) — Ruby idiom; ruby_style.yml.
- The Rails Doctrine — convention over configuration; principles/feedback
  for web/* discipline.
- Tadao Ando, Snøhetta — restraint, negative space, honest material —
  the minimalist aesthetic in principles/feedback_style and flat_pixels.
- Hoefler & Frere-Jones — typographic rhythm and hierarchy — VISUAL_HIERARCHY,
  STEADY_RHYTHM applied to code silhouette as well as type.

## Maintenance

When a rule source is added, moved, or retired, update this file in the
same commit. CANON.md going stale is itself a ONE_SOURCE violation — it is
the index, and a wrong index is worse than no index.
