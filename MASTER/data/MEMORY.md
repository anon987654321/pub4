# MEMORY

Durable user-curated facts for MASTER.

- Keep this file plaintext and editable between turns.
- Store stable facts, preferences, deployment notes, and long-lived project context here.
- Do not paste raw transcripts; summarize facts that should survive compaction.

## Project

- [MASTER project context](claude/project_master.md) — pub4/MASTER constitutional AI agent on dev@brgen.no, OpenRouter API, Ruby/OpenBSD
- [master.yml + master.json are authoritative](claude/project_master_yml_json_authority.md) — current Ruby MASTER must implement what predecessors describe
- [User is an architect](claude/user_architect_aesthetics.md) — aesthetic/typography/design-philosophy proposals usually approved
- [MASTER has two Gemfiles](claude/project_master_dual_gemfile.md) — MASTER/Gemfile and MASTER/web/Gemfile are independent
- [Falcon + EM = subprocess](claude/project_falcon_em_subprocess.md) — Process.fork in a Falcon fiber raises "Closing scheduler"
- [Defrag plan 2026-05](claude/project_defrag_plan_2026_05.md) — data/ shrinks, renames; Orient reverted 2026-05-20
- [7-module refactor](claude/project_master_seven_module_refactor.md) — now/loop/judge/voice/ground/reach/trace

## Principles

- [Always autofix](principles/feedback_autofix.md) — run /fix immediately after scan finds violations
- [Frequent git commits](principles/feedback_git_commits.md) — commit after every meaningful change
- [No new files without approval](principles/feedback_no_new_files.md) — edit originals in place
- [Ultra-minimalistic style](principles/feedback_style.md) — cut filler across Ruby, Zsh, HTML, JS
- [No Python](principles/feedback_no_python.md) — Ruby for all scripting
- [Lint/beautify on touch](principles/feedback_lint_beautify.md) — full pass on every edited file
- [Strunk & White](principles/feedback_strunk_white.md) — active voice, omit needless words
- [Voice — terse, unix](principles/feedback_voice_terse_unix.md) — diagnostic style, loop till zero violations
- [Auto-update README](principles/feedback_readme_autoupdate.md) — refresh after behavior changes
- [No heavy work on device](principles/feedback_device_limits.md) — defer large ops to VPS
- [Bare HTML/CSS targeting](principles/feedback_html_css_style.md) — tag helpers, no divitis
- [Zsh discipline in shell](principles/feedback_master_zsh_discipline.md) — banned cmds apply to agent shell too
- [Autoproceed](principles/feedback_autoproceed.md) — execute full backlog after one approval
- [No permission questions](principles/feedback_no_permission_questions.md) — when answer is obvious, act
- [Decisive directives](principles/feedback_decisive_signals.md) — "ship all" = binding authorization
- [No consecutive whitespace](principles/feedback_no_consecutive_whitespace.md) — single space, single blank line max
- [Proper casing](principles/feedback_proper_casing.md) — sentence case; no ASCII decorations
- [Restart MASTER after web edit](principles/feedback_restart_rails.md) — `doas rcctl restart master`
- [Importance-ordered layout](principles/feedback_importance_order.md) — public API first, helpers last
- [Reassess comments on touch](principles/feedback_comments_reassess.md) — delete fluff, rewrite kept ones
- [Meta-architecture framing](principles/feedback_meta_framing.md) — surface what's next after batches
- [Diverged branch sync](principles/feedback_diverged_branch_sync.md) — backup-tag, reset, cherry-pick
- [Run through MASTER = scan+fix+council](principles/feedback_run_through_master_triad.md)
- [No shell piping](principles/feedback_no_shell_piping.md) — pure Ruby/zsh patterns

## Reference

- [OpenCrabs](claude/reference_opencrabs.md) — Rust MASTER cousin; FTS5 memory, /rebuild
- [Grok UI/CLI patterns](claude/reference_grok_ui_cli_patterns.md) — htmx+SSE, tty-prompt, char-stream CLI