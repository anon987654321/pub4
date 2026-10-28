# Agent configuration preserved outside the repository root

The repository root is constrained to four tracked directories: `MASTER/`,
`RAILS/`, `OPENBSD/` and `STUDIO/`. The former root `.claude/` and
`.github/` directories were moved here to satisfy that contract.

- `claude/settings.json` preserves the former Claude Code project permissions
  and hook definitions. It is **not auto-loaded** at this path; do not mistake
  a preserved settings file for active enforcement.
- `github/copilot-instructions.md` preserves the former Copilot instructions.
  It is an archive copy, not the standard auto-discovered path. Root
  `AGENTS.md`, `CLAUDE.md` and `GEMINI.md` remain root files.

This creates a tooling/structure conflict with the generated `.github`
instruction path and Claude Code's root `.claude/settings.json`. Keep this
conflict open in `TODO.md`. Reconcile it only after reading every file in
`MASTER/` in full, as required by the repository owner; do not copy governance
or generated policy into a competing source of truth.
