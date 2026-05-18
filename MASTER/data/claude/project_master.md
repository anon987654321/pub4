---
name: MASTER project context
description: pub4/MASTER — constitutional AI coding agent on OpenBSD VPS dev@brgen.no
type: project
originSessionId: 84fcf91d-46ea-43a5-8efa-3d33b065e6a5
---
VPS: dev@brgen.no (46.23.89.226), OpenBSD 7.8, 1GB RAM, passwordless doas.
SSH: `sshpass -p '<pass>' ssh -o StrictHostKeyChecking=no dev@46.23.89.226 'cmd'`
Password changes each session — check CLAUDE.md for current.
Codebase: ~/pub4/MASTER/ — Ruby ~6K LOC, Zeitwerk-autoloaded.

**Why:** MASTER is a constitutional AI coding agent that replaces Claude Code CLI. Runs on OpenRouter (default: nvidia/nemotron-3-super-120b-a12b:free) via `ruby_llm` gem. Fallback chain: qwen3-coder:free → minimax-m2.5:free → gpt-oss-120b:free → gemini-2.0-flash.

**How to apply:** All coding work must be done directly on the VPS via sshpass SSH. Never use local tools to edit VPS files — write patch scripts to ~/pub4/tmp/patch.rb and run with ruby. Use zsh builtins only — no sed/awk/grep/find/head/tail.

Pipeline: Intake → Infer → Route → Guard → Execute → [Council ‖ Lint] → Prune → Memo → Render
Pipe mode: `echo "cmd" | bundle exec ruby bin/cli`
Session Startup: read data/standing_orders.yml, data/workflow.yml, data/rules.yml, data/models.yml
Web UI: Rails 8 + Falcon on port 10002, proxied by relayd → ai.brgen.no:3000/4430
