---
name: MASTER project context
description: pub4/MASTER — constitutional AI coding agent on OpenBSD VPS dev@brgen.no
type: project
originSessionId: 84fcf91d-46ea-43a5-8efa-3d33b065e6a5
---
VPS: dev@brgen.no (46.23.89.226), OpenBSD 7.8, 1GB RAM, passwordless doas.
SSH: `sshpass -p '<pass>' ssh -o StrictHostKeyChecking=no dev@46.23.89.226 'cmd'` — password per session; see DEPLOY/OPERATOR.md.
Codebase: ~/pub4/MASTER/ — Ruby ~6K LOC, Zeitwerk-autoloaded.

Constitutional AI agent replacing Claude Code CLI. OpenRouter via `ruby_llm` (default: nvidia/nemotron-3-super-120b-a12b:free). Fallback: qwen3-coder:free → minimax-m2.5:free → gpt-oss-120b:free → gemini-2.0-flash.

All coding on VPS via sshpass SSH — never local edits. Patch via ~/pub4/tmp/patch.rb. Zsh builtins only; no sed/awk/grep/find/head/tail.

Pipeline: Intake → Infer → Route → Guard → Execute → [Council ‖ Lint] → Prune → Memo → Render.
Pipe: `echo "cmd" | bundle exec ruby bin/cli`.
Startup YAML: state.yml, limits.yml, rules.yml, voice.yml, style.yml, models.yml.
Web: Rails 8 + Falcon :53187, relayd → https://ai.brgen.no (443).