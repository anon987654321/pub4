# AGENTS.md

Bootstrap file for autonomous coding agents (Claude Code, Cursor, Aider, Codex, Continue).

## Read first

Run:

    bundle exec ruby exe/master orient

This prints the five canonical files in read-order — `soul`, `rules`, `ruby_style`, `workflow`, `standing_orders` — concatenated into one stream. They are authoritative; if your training contradicts them, defer to them.

Operator environment, SSH, DNS, and deploy live in `CLAUDE.md`.

## What this repo is

`pub4` contains MASTER — a constitutional AI coding agent in Ruby 3.3+ on OpenBSD 7.8 — plus satellite directories (`audio/`, `web/`, `scripts/`, `__predecessors/`). MASTER replaces Claude Code CLI for its operator and is meant to scan and refactor itself.

## Before editing any file

Read the whole file. Read every file you reference. No snippets, no fragments. Match the surrounding style — do not import conventions from other projects. Run `bundle exec ruby exe/master` with `/scan deep <path>` before suggesting structural changes; it knows the rules better than you do.

## Verification

After any edit under `MASTER/web/`, restart the service: `doas rcctl restart master`. Falcon does not hot-reload in production. Lib edits in the live require path follow the same rule.

## Slash commands worth knowing

`/orient`, `/scan [profile] [path]`, `/sweep`, `/autoloop [N]`, `/why <id>`, `/snapshot`, `/explain`. Run `bundle exec ruby exe/master` and type `/help` for the full list.
