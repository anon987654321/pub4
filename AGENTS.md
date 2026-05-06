# AGENTS.md

Bootstrap file for autonomous coding agents (Claude Code, Cursor, Aider, Codex, Continue, etc.).

## Read first, in this order

1. `CLAUDE.md` — operator preferences, environment, git remote, house rules.
2. `MASTER/CONVENTIONS.md` — distilled coding rules, voice, thresholds, banned patterns.
3. `MASTER/data/soul.yml` — constitutional axioms and protection tiers.
4. `MASTER/data/rules.yml` — structural rules and zen principles.
5. `MASTER/data/ruby_style.yml` — Ruby/zsh/OpenBSD style and bug list.

These files are authoritative. If your training contradicts them, defer to them.

## What this repo is

`pub4` contains MASTER — a constitutional AI coding agent in Ruby 3.3+ on OpenBSD 7.8 — and a few satellite directories (`DEPLOY/`, `mix/`, `sh/`, `__predecessors/`). MASTER replaces Claude Code CLI for its operator and is meant to scan and refactor itself.

## Before editing any file

- Read the whole file first. Read every file you reference. No snippets, no fragments.
- Check existing patterns. Match the surrounding style — do not import conventions from other projects.
- Run `MASTER/exe/master` with `/scan deep <path>` before suggesting structural changes; it knows the rules better than you do.

## Banned in this repo

- `sed`, `awk`, `tr`, `grep`, `cut`, `head`, `tail`, `find`, `wc`, `sudo`, `perl`, `python`, `dd`, `xargs` in zsh scripts and SSH commands. Use zsh builtins, parameter expansion, `doas`, or Ruby.
- ASCII line art (`===`, `----`, `•`, `|`, `[ok]`, banner boxes) anywhere — code, comments, commits, CLI output.
- New files unless explicitly approved. Edit originals in place.
- Python for any task. Ruby only.

## Communication

Two registers, never mixed:
- MASTER's own log lines: lowercase, terse, kernel-ish dmesg style.
- Replies to the operator: plain English, proper casing, full sentences. Outcome first.

Commit messages: active voice, concrete verbs, omit needless words. Strunk & White.

## Verification

After any edit under `MASTER/web/`, restart the service: `doas rcctl restart master`. Falcon does not hot-reload in production. Lib edits in the live require path follow the same rule.

## Slash commands worth knowing

`/scan [profile] [path]`, `/sweep`, `/autoloop [N]`, `/why <id>`, `/snapshot`, `/explain`. Run `MASTER/exe/master` and type `/help` for the full list.
